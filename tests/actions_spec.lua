local assert = require("luassert")
local actions = require("clearhead.actions")

-- Needs the real `actions` tree-sitter parser (parser/actions.so on the
-- runtimepath); reported as pending where it is not installed.
describe("actions resolve the action on the cursor line", function()
	local lines = {
		"[ ] Parent #01a0f0ba-0000-7000-8000-000000000001",
		"    >[ ] Child #01a0f0ba-0000-7000-8000-000000000002",
		"    >[ ] Sibling #01a0f0ba-0000-7000-8000-000000000003",
		"[ ] Lone root",
	}

	before_each(function()
		vim.cmd("enew!")
		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	end)

	after_each(function()
		vim.cmd("bwipeout!")
	end)

	-- Neovim 0.12 returns nil for a missing parser instead of throwing.
	local function parser_available()
		local ok, parser = pcall(vim.treesitter.get_parser, 0, "actions")
		return ok and parser ~= nil
	end

	local function id_on(line)
		vim.api.nvim_win_set_cursor(0, { line, 0 })
		return actions.id_under_cursor()
	end

	it("reads the id of the action on the line, not its parent's", function()
		if not parser_available() then
			pending("actions tree-sitter parser is not installed")
			return
		end
		assert.are.equal("01a0f0ba-0000-7000-8000-000000000001", id_on(1))
		assert.are.equal("01a0f0ba-0000-7000-8000-000000000002", id_on(2))
		assert.is_nil(id_on(4))
	end)

	it("set_state_tree on a child touches only that child", function()
		if not parser_available() then
			pending("actions tree-sitter parser is not installed")
			return
		end
		actions.set_state_tree(0, 1, "_")
		local got = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		assert.are.same({ lines[1], (lines[2]:gsub("%[ %]", "[_]")), lines[3], lines[4] }, got)
	end)

	it("set_state_tree finds a childless root action", function()
		if not parser_available() then
			pending("actions tree-sitter parser is not installed")
			return
		end
		actions.set_state_tree(0, 3, "-")
		assert.are.equal("[-] Lone root", vim.api.nvim_buf_get_lines(0, 3, 4, false)[1])
	end)
end)
