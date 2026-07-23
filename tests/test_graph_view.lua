-- Standalone graph-view projection test.
-- Run: LUA_PATH="./lua/?.lua;./lua/?/init.lua;;" nvim -l tests/test_graph_view.lua
local query = require("clearhead.query")
local graph_view = require("clearhead.graph_view")

local function fail(message)
	print("FAIL: " .. message)
	os.exit(1)
end

local dot = [[digraph {
  0 [label="prepare"]
  1 [label="ship"]
  0 -> 1
}
]]

query.run_graph = function(name, callback)
	if name ~= "dependencies" then
		fail("unexpected query name: " .. tostring(name))
	end
	callback(dot)
end

graph_view.open("dependencies")
local bufnr = vim.api.nvim_get_current_buf()
if vim.bo[bufnr].filetype ~= "dot" or vim.bo[bufnr].buftype ~= "nofile" then
	fail("graph view is not a DOT scratch buffer")
end
if vim.bo[bufnr].modifiable then
	fail("graph view must be read-only")
end
local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
if not content:find("0 -> 1", 1, true) then
	fail("DOT dependency edge missing from buffer")
end
print("PASS: graph query opens as a read-only DOT buffer")

graph_view.open("dependencies")
if vim.api.nvim_get_current_buf() ~= bufnr then
	fail("opening the same query did not reuse its graph buffer")
end
print("PASS: reopening refreshes the existing graph buffer")

if vim.fn.executable("dot") == 1 then
	local opened
	local old_open = vim.ui.open
	vim.ui.open = function(path)
		opened = path
	end
	graph_view.preview(bufnr)
	if not vim.wait(5000, function()
		return opened ~= nil
	end, 25) then
		fail("Graphviz preview did not open an SVG")
	end
	vim.ui.open = old_open
	if not opened:match("%.svg$") or vim.fn.filereadable(opened) ~= 1 then
		fail("preview did not produce an SVG file")
	end
	print("PASS: Graphviz preview renders and opens SVG")
end

print("All graph view tests passed!")
