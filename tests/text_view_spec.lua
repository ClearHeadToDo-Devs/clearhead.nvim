local assert = require("luassert")
local config = require("clearhead.config")
local text_view = require("clearhead.text_view")

describe("text view", function()
	local original_bin

	before_each(function()
		original_bin = config.get_bin_path
		-- `echo` stands in for the CLI: its output is its argv, so the buffer
		-- shows exactly which command line ran.
		config.get_bin_path = function()
			return "echo"
		end
	end)

	after_each(function()
		config.get_bin_path = original_bin
		vim.cmd("silent! %bwipeout!")
	end)

	local function open_and_wait(args)
		text_view.open(args)
		local name = "clearhead://" .. table.concat(args, "/")
		vim.wait(2000, function()
			return vim.fn.bufnr(name) ~= -1
		end)
		return vim.fn.bufnr(name)
	end

	it("shows the command's stdout in a read-only scratch buffer", function()
		local bufnr = open_and_wait({ "debug" })
		assert.are_not.equal(-1, bufnr)
		assert.are.same({ "debug" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
		assert.are.equal("nofile", vim.bo[bufnr].buftype)
		assert.is_false(vim.bo[bufnr].modifiable)
	end)

	it("reuses the buffer for the same command line", function()
		local first = open_and_wait({ "debug" })
		local windows = #vim.api.nvim_list_wins()
		local second = open_and_wait({ "debug" })
		vim.wait(200)
		assert.are.equal(first, second)
		assert.are.equal(windows, #vim.api.nvim_list_wins())
	end)
end)
