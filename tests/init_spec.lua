local async = require("plenary.async.tests")
local neotest_deno = require("neotest-deno")

local it = async.it
local describe = async.describe

describe("DenoNeotestAdapter.init", function()

	it("has the correct name", function()

		assert.equals(neotest_deno.name, "neotest-deno")
	end)
end)

describe("DenoNeotestAdapter.is_test_file", function()

	local nix_src_dir = "/home/user/deno/app"
	local win_src_dir = "C:\\Users\\user\\Documents\\deno\\app"

	local valid_exts = {
		'js',
		'ts',
		'tsx',
		'mts',
		'mjs',
		'jsx',
		'cjs',
		'cts',
	}

	describe("Validates unix-style paths", function()

		it("recognizes files named test.<ext>", function()

			for _, ext in pairs(valid_exts) do
				local fn = nix_src_dir .. '/test.' .. ext
				assert.True(neotest_deno.is_test_file(fn))
			end
		end)

		it("recognizes files named *.test.<ext>", function()

			for _, ext in pairs(valid_exts) do
				local fn = nix_src_dir .. '/app.test.' .. ext
				assert.True(neotest_deno.is_test_file(fn))
			end
		end)

		it("recognizes files named *_test.<ext>", function()

			for _, ext in pairs(valid_exts) do
				local fn = nix_src_dir .. '/app_test.' .. ext
				assert.True(neotest_deno.is_test_file(fn))
			end
		end)

		it("rejects files with invalid names", function()

			assert.False(neotest_deno.is_test_file(nix_src_dir .. '/apptest.ts'))
			assert.False(neotest_deno.is_test_file(nix_src_dir .. '/Test.js'))
			assert.False(neotest_deno.is_test_file(nix_src_dir .. '/app.test.unit.tsx'))
			assert.False(neotest_deno.is_test_file(nix_src_dir .. '/main.jsx'))
			assert.False(neotest_deno.is_test_file(nix_src_dir .. '/app_Test.mts'))
		end)

		it("rejects files with invalid extensions", function()

			assert.False(neotest_deno.is_test_file(nix_src_dir .. '/test.json'))
			assert.False(neotest_deno.is_test_file(nix_src_dir .. '/app.test.rs'))
			assert.False(neotest_deno.is_test_file(nix_src_dir .. '/app_test.md'))
		end)
	end)

	describe("Validates Windows-style paths", function()

		it("recognizes files named test.<ext>", function()

			for _, ext in pairs(valid_exts) do
				local fn = win_src_dir .. '\\test.' .. ext
				assert.True(neotest_deno.is_test_file(fn))
			end
		end)

		it("recognizes files named *.test.<ext>", function()

			for _, ext in pairs(valid_exts) do
				local fn = win_src_dir .. '\\app.test.' .. ext
				assert.True(neotest_deno.is_test_file(fn))
			end
		end)

		it("recognizes files named *_test.<ext>", function()

			for _, ext in pairs(valid_exts) do
				local fn = win_src_dir .. '\\app_test.' .. ext
				assert.True(neotest_deno.is_test_file(fn))
			end
		end)

		it("rejects files with invalid names", function()

			assert.False(neotest_deno.is_test_file(win_src_dir .. '\\apptest.ts'))
			assert.False(neotest_deno.is_test_file(win_src_dir .. '\\Test.js'))
			assert.False(neotest_deno.is_test_file(win_src_dir .. '\\app.test.unit.tsx'))
			assert.False(neotest_deno.is_test_file(win_src_dir .. '\\main.jsx'))
			assert.False(neotest_deno.is_test_file(win_src_dir .. '\\app_Test.mts'))
		end)

		it("rejects files with invalid extensions", function()

			assert.False(neotest_deno.is_test_file(win_src_dir .. '\\test.json'))
			assert.False(neotest_deno.is_test_file(win_src_dir .. '\\app.test.rs'))
			assert.False(neotest_deno.is_test_file(win_src_dir .. '\\app_test.md'))
		end)
	end)


end)

describe("DenoNeotestAdapter.discover_positions", function()

	it("discovers basic Deno.test calls", function()
		local temp_file = vim.fn.tempname() .. ".test.ts"
		local content = [[
import { expect } from "@std/expect";

Deno.test("simple test", () => {
    expect(1 + 1).toBe(2);
});

Deno.test("async test", async () => {
    const result = await Promise.resolve(42);
    expect(result).toBe(42);
});
]]
		vim.fn.writefile(vim.split(content, "\n"), temp_file)
		
		local positions = neotest_deno.discover_positions(temp_file)
		
		assert.is_not_nil(positions)
		assert.equals(positions:data().type, "file")
		
		local children = positions:children()
		assert.equals(#children, 2)
		
		-- Check first test
		assert.equals(children[1]:data().type, "test")
		assert.equals(children[1]:data().name, '"simple test"')
		
		-- Check second test
		assert.equals(children[2]:data().type, "test")
		assert.equals(children[2]:data().name, '"async test"')
		
		vim.fn.delete(temp_file)
	end)

	it("discovers nested test steps", function()
		local temp_file = vim.fn.tempname() .. ".test.ts"
		local content = [[
import { expect } from "@std/expect";

Deno.test("Top-level test", async (t) => {
    await t.step("First nested test", () => {
        expect(1 + 1).toBe(2);
    });

    await t.step("Second-level nested test", async (t) => {
        await t.step("Third-level nested test", () => {
            expect(2 * 2).toBe(4);
        });

        await t.step("Another third-level nested test", () => {
            expect(3 - 1).toBe(2);
        });
    });
});
]]
		vim.fn.writefile(vim.split(content, "\n"), temp_file)
		
		local positions = neotest_deno.discover_positions(temp_file)
		
		assert.is_not_nil(positions)
		assert.equals(positions:data().type, "file")
		
		local children = positions:children()
		assert.equals(#children, 1)
		
		-- Check top-level test
		local top_test = children[1]
		assert.equals(top_test:data().type, "test")
		assert.equals(top_test:data().name, '"Top-level test"')
		
		-- Check nested steps
		local nested_steps = top_test:children()
		assert.equals(#nested_steps, 2)
		
		-- First step
		assert.equals(nested_steps[1]:data().type, "test")
		assert.equals(nested_steps[1]:data().name, '"First nested test"')
		
		-- Second step with its own nested steps
		assert.equals(nested_steps[2]:data().type, "test")
		assert.equals(nested_steps[2]:data().name, '"Second-level nested test"')
		
		local third_level_steps = nested_steps[2]:children()
		assert.equals(#third_level_steps, 2)
		
		assert.equals(third_level_steps[1]:data().type, "test")
		assert.equals(third_level_steps[1]:data().name, '"Third-level nested test"')
		
		assert.equals(third_level_steps[2]:data().type, "test")
		assert.equals(third_level_steps[2]:data().name, '"Another third-level nested test"')
		
		vim.fn.delete(temp_file)
	end)

	it("discovers mixed Deno.test and nested steps", function()
		local temp_file = vim.fn.tempname() .. ".test.ts"
		local content = [[
import { expect } from "@std/expect";

Deno.test("standalone test", () => {
    expect(true).toBe(true);
});

Deno.test("test with steps", async (t) => {
    await t.step("nested step 1", () => {
        expect(1).toBe(1);
    });
    
    await t.step("nested step 2", () => {
        expect(2).toBe(2);
    });
});
]]
		vim.fn.writefile(vim.split(content, "\n"), temp_file)
		
		local positions = neotest_deno.discover_positions(temp_file)
		
		assert.is_not_nil(positions)
		assert.equals(positions:data().type, "file")
		
		local children = positions:children()
		assert.equals(#children, 2)
		
		-- Check standalone test
		assert.equals(children[1]:data().type, "test")
		assert.equals(children[1]:data().name, '"standalone test"')
		assert.equals(#children[1]:children(), 0)
		
		-- Check test with steps
		assert.equals(children[2]:data().type, "test")
		assert.equals(children[2]:data().name, '"test with steps"')
		
		local steps = children[2]:children()
		assert.equals(#steps, 2)
		
		assert.equals(steps[1]:data().type, "test")
		assert.equals(steps[1]:data().name, '"nested step 1"')
		
		assert.equals(steps[2]:data().type, "test")
		assert.equals(steps[2]:data().name, '"nested step 2"')
		
		vim.fn.delete(temp_file)
	end)

	it("discovers BDD style tests with describe and it", function()
		local temp_file = vim.fn.tempname() .. ".test.ts"
		local content = [[
import { describe, it } from "@std/testing/bdd";
import { expect } from "@std/expect";

describe("Math operations", () => {
    it("should add numbers correctly", () => {
        expect(1 + 1).toBe(2);
    });
    
    it("should subtract numbers correctly", () => {
        expect(3 - 1).toBe(2);
    });
});
]]
		vim.fn.writefile(vim.split(content, "\n"), temp_file)
		
		local positions = neotest_deno.discover_positions(temp_file)
		
		assert.is_not_nil(positions)
		assert.equals(positions:data().type, "file")
		
		local children = positions:children()
		assert.equals(#children, 1)
		
		-- Check describe block
		local describe_block = children[1]
		assert.equals(describe_block:data().type, "namespace")
		assert.equals(describe_block:data().name, '"Math operations"')
		
		-- Check it blocks
		local it_blocks = describe_block:children()
		assert.equals(#it_blocks, 2)
		
		assert.equals(it_blocks[1]:data().type, "test")
		assert.equals(it_blocks[1]:data().name, '"should add numbers correctly"')
		
		assert.equals(it_blocks[2]:data().type, "test")
		assert.equals(it_blocks[2]:data().name, '"should subtract numbers correctly"')
		
		vim.fn.delete(temp_file)
	end)

	it("returns nil for non-test files", function()
		local temp_file = vim.fn.tempname() .. ".js"
		local content = [[
console.log("This is not a test file");
]]
		vim.fn.writefile(vim.split(content, "\n"), temp_file)
		
		local positions = neotest_deno.discover_positions(temp_file)
		
		-- Should still return a tree for valid file extensions, even if no tests found
		assert.is_not_nil(positions)
		assert.equals(positions:data().type, "file")
		assert.equals(#positions:children(), 0)
		
		vim.fn.delete(temp_file)
	end)
end)

-- TODO: More tests!
--describe("DenoNeotestAdapter.root", function()
--end)
--
--describe("DenoNeotestAdapter.filter_dir", function()
--end)
--
--describe("DenoNeotestAdapter.build_spec", function()
--end)
--
--describe("DenoNeotestAdapter.results", function()
--end)
