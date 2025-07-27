local lib = require("neotest.lib")
local utils = require("neotest-deno.utils")
local config = require("neotest-deno.config")

---@class neotest.Adapter
---@field name string
local DenoNeotestAdapter = { name = "neotest-deno" }

-- Store test module data from LSP notifications
local test_modules = {}
local lsp_client = nil

-- Helper function to get or find Deno LSP client
local function get_deno_lsp_client()
	if lsp_client then
		return lsp_client
	end
	
	local clients = vim.lsp.get_active_clients()
	for _, client in ipairs(clients) do
		if client.name == "denols" then
			lsp_client = client
			return client
		end
	end
	return nil
end

-- Set up LSP testing capabilities and notifications
local function setup_lsp_testing()
	local client = get_deno_lsp_client()
	if not client then
		return false
	end
	
	-- Check if LSP supports testing API
	if not (client.server_capabilities.experimental and 
	        client.server_capabilities.experimental.testingApi) then
		-- LSP doesn't support testing API, use fallback
		return false
	end
	
	-- Register for test module notifications
	client.handlers["deno/testModule"] = function(_, result, _)
		if not result or not result.textDocument then
			return
		end
		
		if result.kind == "replace" then
			test_modules[result.textDocument.uri] = result
		elseif result.kind == "insert" then
			local existing = test_modules[result.textDocument.uri]
			if existing and existing.tests then
				-- Merge the new tests with existing ones
				for _, test in ipairs(result.tests or {}) do
					table.insert(existing.tests, test)
				end
			else
				test_modules[result.textDocument.uri] = result
			end
		end
	end
	
	client.handlers["deno/testModuleDelete"] = function(_, result, _)
		if result and result.textDocument then
			test_modules[result.textDocument.uri] = nil
		end
	end
	
	return true
end

---Find the project root directory given a current directory to work from.
---Should no root be found, the adapter can still be used in a non-project context if a test file matches.
---@async
---@param dir string @Directory to treat as cwd
---@return string | nil @Absolute root dir of test suite
function DenoNeotestAdapter.root(dir)

	local result = nil
	local root_files = vim.list_extend(
		config.get_additional_root_files(),
		{ "deno.json", "deno.jsonc", "import_map.json" }
	)

	for _, root_file in ipairs(root_files) do
		result = lib.files.match_root_pattern(root_file)(dir)
		if result then
			break
		end
	end

	return result
end

---Filter directories when searching for test files
---@async
---@param name string Name of directory
---!param rel_path string Path to directory, relative to root
---!param root string Root directory of project
function DenoNeotestAdapter.filter_dir(name)

	local filter_dirs = vim.list_extend(
		config.get_additional_filter_dirs(),
		{ "node_modules" }
	)

	for _, filter_dir in ipairs(filter_dirs) do
		if name == filter_dir then
			return false
		end
	end

	return true
end

---@async
---@param file_path string
---@return boolean
function DenoNeotestAdapter.is_test_file(file_path)

	-- See https://deno.land/manual@v1.27.2/basics/testing#running-tests
	local valid_exts = {
		js = true,
		ts = true,
		tsx = true,
		mts = true,
		mjs = true,
		jsx = true,
		cjs = true,
		cts = true,
	}

	-- Get filename
	local file_name = string.match(file_path, ".-([^\\/]-%.?[^%.\\/]*)$")

	-- filename match _ . or test.
	local ext = string.match(file_name, "[_%.]test%.(%w+)$") or	-- Filename ends in _test.<ext> or .test.<ext>
		string.match(file_name, "^test%.(%w+)$") or				-- Filename is test.<ext>
		nil

	if ext and valid_exts[ext] then
		return true
	end

	return false
end

---Given a file path, parse all the tests within it.
---@async
---@param file_path string Absolute file path
---@return neotest.Tree | nil
function DenoNeotestAdapter.discover_positions(file_path)
	-- Check if LSP testing is enabled and available
	if config.get_use_lsp_testing() and setup_lsp_testing() then
		local file_uri = vim.uri_from_fname(file_path)
		local module_data = test_modules[file_uri]
		
		if module_data then
			-- Convert LSP test data to neotest tree structure
			return convert_lsp_tests_to_tree(file_path, module_data)
		end
	end
	
	-- Fallback to TreeSitter parsing
	return fallback_treesitter_discovery(file_path)
end

-- Convert LSP TestData to neotest tree nodes
local function convert_test_data_to_node(test_data, file_path)
	local node_data = {
		id = file_path .. "::" .. test_data.id,
		name = test_data.label,
		type = "test",
		path = file_path,
		range = test_data.range and {
			test_data.range.start.line + 1,
			test_data.range.start.character,
			test_data.range["end"].line + 1,
			test_data.range["end"].character
		} or nil
	}
	
	local children = {}
	if test_data.steps then
		for _, step in ipairs(test_data.steps) do
			table.insert(children, convert_test_data_to_node(step, file_path))
		end
	end
	
	return lib.Tree:new(node_data, children)
end

-- Convert LSP test module data to neotest tree
function convert_lsp_tests_to_tree(file_path, module_data)
	if not module_data or not module_data.tests then
		return nil
	end
	
	local children = {}
	
	for _, test in ipairs(module_data.tests) do
		local child_node = convert_test_data_to_node(test, file_path)
		if child_node then
			table.insert(children, child_node)
		end
	end
	
	local root_data = {
		id = file_path,
		name = vim.fn.fnamemodify(file_path, ":t"),
		type = "file",
		path = file_path
	}
	
	return lib.Tree:new(root_data, children)
end

-- Fallback TreeSitter-based discovery for when LSP is not available
function fallback_treesitter_discovery(file_path)
	local query = [[
;; Deno.test
(call_expression
	function: (member_expression) @func_name (#match? @func_name "^Deno.test$")
	arguments: [
		(arguments ((string) @test.name . (arrow_function)))
		(arguments . (function name: (identifier) @test.name))
		(arguments . (object(pair
			key: (property_identifier) @key (#match? @key "^name$")
			value: (string) @test.name
		)))
		(arguments ((string) @test.name . (object) . (arrow_function)))
		(arguments (object) . (function name: (identifier) @test.name))
	]
) @test.definition

;; Deno test steps - nested tests using t.step()
(await_expression
	argument: (call_expression
		function: (member_expression
			object: (identifier) @t_param
			property: (property_identifier) @step_method (#match? @step_method "^step$")
		) @func_name
		arguments: [
			(arguments ((string) @test.name . (arrow_function)))
			(arguments ((string) @test.name . (function)))
		]
	)
) @test.definition

;; BDD describe - nested
(call_expression
	function: (identifier) @func_name (#match? @func_name "^describe$")
	arguments: [
		(arguments ((string) @namespace.name . (arrow_function)))
		(arguments ((string) @namespace.name . (function)))
	]
) @namespace.definition

;; BDD describe - flat
(variable_declarator
	name: (identifier) @namespace.id
	value: (call_expression
		function: (identifier) @func_name (#match? @func_name "^describe")
		arguments: [
			(arguments ((string) @namespace.name))
			(arguments (object (pair
				key: (property_identifier) @key (#match? @key "^name$")
				value: (string) @namespace.name
			)))
		]
	)
) @namespace.definition

;; BDD it
(call_expression
	function: (identifier) @func_name (#match? @func_name "^it$")
	arguments: [
		(arguments ((string) @test.name . (arrow_function)))
		(arguments ((string) @test.name . (function)))
	]
) @test.definition
	]]

	local position_tree = lib.treesitter.parse_positions(
		file_path,
		query,
		{ nested_namespaces = true }
	)

	return position_tree
end

---@param args neotest.RunArgs
---@return nil | neotest.RunSpec | neotest.RunSpec[]
function DenoNeotestAdapter.build_spec(args)

	local results_path = utils.get_results_file()
    local position = args.tree:data()
	local strategy = {}

	local cwd = assert(
		DenoNeotestAdapter.root(position.path),
		"could not locate root directory of " .. position.path
	)

    local command_args = vim.tbl_flatten({
		"test",
		position.path,
		"--no-prompt",
		vim.list_extend(config.get_args(), args.extra_args or {}),
		config.get_allow() or "--allow-all",
    })

	-- Handle test filtering for specific tests or steps
	if position.type == "test" then
		local test_name = position.name
		if args.strategy == "dap" then
			test_name = test_name:gsub('^"', ''):gsub('"$', '')
		end

		-- For LSP-discovered tests, use the test ID if available
		local test_id = position.id
		if test_id and test_id:match("::") then
			-- Extract the LSP test ID from the position ID
			local lsp_id = test_id:match("::(.+)$")
			if lsp_id then
				-- Try to use LSP test running if available
				local client = get_deno_lsp_client()
				if client and client.server_capabilities.experimental and 
				   client.server_capabilities.experimental.testingApi then
					-- TODO: Implement LSP-based test running
					-- For now, fall back to filter-based approach
				end
			end
		end

        vim.list_extend(command_args, { "--filter", test_name })
	end

	-- BUG: Need to capture results after debugging the test
	-- TODO: Adding additional arguments breaks debugging
	-- need to determine if this is normal
	if args.strategy == "dap" then

		-- TODO: Allow users to specify an alternate port =HOST:PORT
		vim.list_extend(command_args, { "--inspect-brk" })

		strategy = {
			name = 'Deno',
			type = config.get_dap_adapter(),
			request = 'launch',
			cwd = '${workspaceFolder}',
			runtimeExecutable = 'deno',
			runtimeArgs = command_args,
			port = 9229,
			protocol = 'inspector',
		}
	end

	return {
		command = 'deno ' .. table.concat(command_args, " "),
		context = {
			results_path = results_path,
			position = position,
		},
		cwd = cwd,
		strategy = strategy,
	}
end

---@async
---@param spec neotest.RunSpec
---!param result neotest.StrategyResult
---!param tree neotest.Tree
---@return table<string, neotest.Result>
function DenoNeotestAdapter.results(spec)

    local results = {}
	local file_path = ''
	local handle = assert(io.open(spec.context.results_path))
	local line = handle:read("l")
	local current_test_context = {} -- Stack to track nested test context

	while line do
		-- Extract test file path
		if string.find(line, 'running %d+ test') then
			local testfile = string.match(line, 'running %d+ tests? from %.(.+)$')
			if testfile then
				file_path = spec.cwd .. "/" .. testfile
			end

		-- Handle test results with indentation for nested steps
		elseif string.find(line, '%.%.%. ok') then
			local test_name = utils.get_test_name_from_result(line)
			if test_name then
				local full_path = file_path .. "::" .. test_name
				results[full_path] = { status = "passed" }
			end

		elseif string.find(line, '%.%.%. FAILED') then
			local test_name = utils.get_test_name_from_result(line)
			if test_name then
				-- Read error details
				local error_output = {}
				local next_line = handle:read("l")
				
				while next_line and not string.find(next_line, '^[%w]') and
					  not string.find(next_line, 'running %d+ test') do
					table.insert(error_output, next_line)
					next_line = handle:read("l")
				end
				
				local full_path = file_path .. "::" .. test_name
				results[full_path] = { 
					status = "failed",
					short = table.concat(error_output, "\n"),
					output = table.concat(error_output, "\n")
				}
				
				-- Process the line we read ahead
				if next_line then
					line = next_line
					goto continue
				end
			end
		end

		line = handle:read("l")
		::continue::
	end

	if handle then
		handle:close()
	end

    return results
end

setmetatable(DenoNeotestAdapter, {
	__call = function(_, opts)
		if utils.is_callable(opts.args) then
			config.get_args = opts.args
		elseif opts.args then
			config.get_args = function()
				return opts.args
			end
		end
		if utils.is_callable(opts.allow) then
			config.get_allow = opts.allow
		elseif opts.allow then
			config.get_allow = function()
				return opts.allow
			end
		end
		if utils.is_callable(opts.root_files) then
			config.get_additional_root_files = opts.root_files
		elseif opts.root_files then
			config.get_additional_root_files = function()
				return opts.root_files
			end
		end
		if utils.is_callable(opts.filter_dirs) then
			config.get_additional_filter_dirs = opts.filter_dirs
		elseif opts.filter_dirs then
			config.get_additional_filter_dirs = function()
				return opts.filter_dirs
			end
		end
		if utils.is_callable(opts.dap_adapter) then
			config.get_dap_adapter = opts.dap_adapter
		elseif opts.dap_adapter then
			config.get_dap_adapter = function()
				return opts.dap_adapter
			end
		end
		if utils.is_callable(opts.use_lsp_testing) then
			config.get_use_lsp_testing = opts.use_lsp_testing
		elseif opts.use_lsp_testing ~= nil then
			config.get_use_lsp_testing = function()
				return opts.use_lsp_testing
			end
		end
		return DenoNeotestAdapter
	end,
})

return DenoNeotestAdapter
