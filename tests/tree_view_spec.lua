local assert = require("luassert")
local query = require("clearhead.query")
local tree_view = require("clearhead.tree_view")

describe("tree view", function()
	local original_run_tree
	local root
	local charter_root
	local tree

	before_each(function()
		root = vim.fn.tempname()
		charter_root = root .. "/.clearhead/charters"
		vim.fn.mkdir(charter_root .. "/work", "p")
		vim.fn.writefile({ "# Work" }, charter_root .. "/work/README.md")
		vim.fn.writefile({ "[ ] Ship" }, charter_root .. "/work/next.actions")

		tree = {
			{
				id = "urn:uuid:charter",
				kind = "charter",
				name = "Work",
				charter_root = charter_root,
				source_file = "work/README.md",
				children = {
					{
						id = "urn:uuid:action",
						kind = "action",
						name = "Ship",
						status = "NotStarted",
						charter_root = charter_root,
						source_file = "work/next.actions",
						source_line = 1,
					},
				},
			},
		}

		original_run_tree = query.run_tree
		---@diagnostic disable-next-line: duplicate-set-field
		query.run_tree = function(name, callback)
			assert.are.equal("work-map", name)
			callback(tree)
		end
	end)

	after_each(function()
		query.run_tree = original_run_tree
		vim.fn.delete(root, "rf")
	end)

	it("renders, toggles, jumps to sources, and reuses its buffer", function()
		tree_view.open("work-map")
		local tree_buf = vim.api.nvim_get_current_buf()
		local tree_win = vim.api.nvim_get_current_win()
		local lines = vim.api.nvim_buf_get_lines(tree_buf, 0, -1, false)
		assert.are.equal(2, #lines)
		assert.is_truthy(lines[1]:find("Work", 1, true))
		assert.is_truthy(lines[2]:find("Ship", 1, true))

		vim.api.nvim_win_set_cursor(tree_win, { 1, 0 })
		tree_view.toggle(tree_buf)
		assert.are.equal(1, #vim.api.nvim_buf_get_lines(tree_buf, 0, -1, false))
		tree_view.toggle(tree_buf)

		vim.api.nvim_win_set_cursor(tree_win, { 1, 0 })
		tree_view.jump(tree_buf)
		assert.are.equal(charter_root .. "/work/README.md", vim.api.nvim_buf_get_name(0))

		vim.api.nvim_set_current_win(tree_win)
		vim.api.nvim_win_set_cursor(tree_win, { 2, 0 })
		tree_view.jump(tree_buf)
		assert.are.equal(charter_root .. "/work/next.actions", vim.api.nvim_buf_get_name(0))

		tree_view.open("work-map")
		assert.are.equal(tree_buf, vim.api.nvim_get_current_buf())
	end)
end)
