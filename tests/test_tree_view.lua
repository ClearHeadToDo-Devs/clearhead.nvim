-- Standalone tree-view projection test.
-- Run: LUA_PATH="./lua/?.lua;./lua/?/init.lua;;" nvim -l tests/test_tree_view.lua
local query = require("clearhead.query")
local tree_view = require("clearhead.tree_view")

local function fail(message)
	print("FAIL: " .. message)
	os.exit(1)
end

local root = vim.fn.tempname()
local charter_root = root .. "/.clearhead/charters"
vim.fn.mkdir(charter_root .. "/work", "p")
vim.fn.writefile({ "# Work" }, charter_root .. "/work/README.md")
vim.fn.writefile({ "[ ] Ship" }, charter_root .. "/work/next.actions")

local tree = {
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

query.run_tree = function(name, callback)
	if name ~= "work-map" then
		fail("unexpected query name: " .. tostring(name))
	end
	callback(tree)
end

tree_view.open("work-map")
local tree_buf = vim.api.nvim_get_current_buf()
local tree_win = vim.api.nvim_get_current_win()
local lines = vim.api.nvim_buf_get_lines(tree_buf, 0, -1, false)
if #lines ~= 2 or not lines[1]:find("Work", 1, true) or not lines[2]:find("Ship", 1, true) then
	fail("tree did not render charter and action hierarchy")
end
print("PASS: tree renders charter and action hierarchy")

vim.api.nvim_win_set_cursor(tree_win, { 1, 0 })
tree_view.toggle(tree_buf)
lines = vim.api.nvim_buf_get_lines(tree_buf, 0, -1, false)
if #lines ~= 1 then
	fail("collapse did not hide descendants")
end
tree_view.toggle(tree_buf)
print("PASS: branches expand and collapse")

vim.api.nvim_win_set_cursor(tree_win, { 1, 0 })
tree_view.jump(tree_buf)
if vim.api.nvim_buf_get_name(0) ~= charter_root .. "/work/README.md" then
	fail("charter node did not open its Markdown source")
end
print("PASS: charter node opens its Markdown source")

vim.api.nvim_set_current_win(tree_win)
vim.api.nvim_win_set_cursor(tree_win, { 2, 0 })
tree_view.jump(tree_buf)
if vim.api.nvim_buf_get_name(0) ~= charter_root .. "/work/next.actions" then
	fail("action node did not open its actions source")
end
print("PASS: action node opens its source line")

tree_view.open("work-map")
if vim.api.nvim_get_current_buf() ~= tree_buf then
	fail("opening the same query did not reuse its tree buffer")
end
print("PASS: reopening refreshes the existing tree buffer")

print("All tree view tests passed!")
