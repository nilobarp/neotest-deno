local M = {}

M.get_args = function()
	return {}
end

M.get_allow = function()
	return nil
end

M.get_additional_root_files = function()
	return {}
end

M.get_additional_filter_dirs = function()
	return {}
end

M.get_dap_adapter = function()
	return 'deno'
end

M.get_use_lsp_testing = function()
	return true  -- Default to using LSP testing interface
end

return M
