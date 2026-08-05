local assert = require("luassert")
local graph_view = require("clearhead.graph_view")
local query = require("clearhead.query")

local DOT = [[digraph {
  0 [label="prepare"]
  1 [label="ship"]
  0 -> 1
}
]]

describe("graph view", function()
	local original_run_graph

	before_each(function()
		original_run_graph = query.run_graph
		---@diagnostic disable-next-line: duplicate-set-field
		query.run_graph = function(name, callback)
			assert.are.equal("dependencies", name)
			callback(DOT)
		end
	end)

	after_each(function()
		query.run_graph = original_run_graph
	end)

	it("opens a read-only DOT buffer and reuses it on refresh", function()
		graph_view.open("dependencies")
		local bufnr = vim.api.nvim_get_current_buf()

		assert.are.equal("dot", vim.bo[bufnr].filetype)
		assert.are.equal("nofile", vim.bo[bufnr].buftype)
		assert.is_false(vim.bo[bufnr].modifiable)
		local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
		assert.is_truthy(content:find("0 -> 1", 1, true))

		graph_view.open("dependencies")
		assert.are.equal(bufnr, vim.api.nvim_get_current_buf())
	end)

	it("renders an SVG preview when Graphviz is available", function()
		if vim.fn.executable("dot") ~= 1 then
			pending("Graphviz is not installed")
			return
		end

		graph_view.open("dependencies")
		local bufnr = vim.api.nvim_get_current_buf()
		local opened
		local original_open = vim.ui.open
		vim.ui.open = function(path)
			opened = path
		end

		graph_view.preview(bufnr)
		local completed = vim.wait(5000, function()
			return opened ~= nil
		end, 25)
		vim.ui.open = original_open

		assert.is_true(completed)
		assert.matches("%.svg$", opened)
		assert.are.equal(1, vim.fn.filereadable(opened))
	end)
end)
