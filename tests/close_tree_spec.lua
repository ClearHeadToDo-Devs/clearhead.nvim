local assert = require("luassert")
local actions = require("clearhead.actions")

describe("close tree preserves closed members", function()
	before_each(function()
		vim.cmd("enew!")
	end)

	after_each(function()
		vim.cmd("bwipeout!")
	end)

	for _, state in ipairs({ "x", "_" }) do
		it("forces the target to " .. state .. " but keeps closed members and walks through them", function()
			local ok, parser = pcall(vim.treesitter.get_parser, 0, "actions")
			if not ok or not parser then
				pending("actions tree-sitter parser is not installed")
				return
			end
			local opposite = state == "x" and "_" or "x"
			local lines = {
				"[" .. opposite .. "] Target %2020-01-01T00:00 $ Keep %123 in prose $",
				">[x] Completed %2020-02-02T00:00",
				">>[ ] Open grandchild",
				">[_] Cancelled %2020-03-03T00:00",
				">[-] Working $ Keep %123 too $",
				">[=] Blocked",
				"[ ] Other root",
			}
			vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
			actions.set_state_tree(0, 0, state)
			local got = vim.api.nvim_buf_get_lines(0, 0, -1, false)
			assert.is_truthy(got[1]:find("[" .. state .. "] Target", 1, true))
			assert.is_falsy(got[1]:find("%2020-01-01T00:00", 1, true))
			assert.is_truthy(got[1]:find("Keep %123 in prose", 1, true))
			for _, row in ipairs({ 1, 3, 5, 6 }) do
				assert.is_truthy(got[row]:find("[" .. state .. "]", 1, true))
				assert.is_truthy(got[row]:match("%%%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d"))
			end
			assert.is_truthy(got[5]:find("Keep %123 too", 1, true))
			assert.are.equal(lines[2], got[2])
			assert.are.equal(lines[4], got[4])
			assert.are.equal(lines[7], got[7])

			vim.bo.modified = false
			actions.set_state_tree(0, 0, state)
			assert.are.same(got, vim.api.nvim_buf_get_lines(0, 0, -1, false))
			assert.is_false(vim.bo.modified)
		end)
	end

	it("keeps the date of a target already in the requested state", function()
		local ok, parser = pcall(vim.treesitter.get_parser, 0, "actions")
		if not ok or not parser then
			pending("actions tree-sitter parser is not installed")
			return
		end
		for _, state in ipairs({ "x", "_" }) do
			local target = "[" .. state .. "] Target %2020-01-01T00:00"
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { target, ">[ ] Open" })
			actions.set_state_tree(0, 0, state)
			assert.are.equal(target, vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])
		end
	end)
end)
