local assert = require("luassert")
local view = require("clearhead.view")

local function wait_for(predicate, description)
	assert.is_true(vim.wait(8000, predicate, 50), "timed out waiting for " .. description)
end

describe("living loop", function()
	it("reads, mutates by id, and re-reads an archived completion", function()
		if vim.fn.executable("clearhead") == 0 then
			pending("clearhead is not available on PATH")
			return
		end

		local root = vim.fn.tempname()
		local charters = root .. "/.clearhead/charters"
		vim.fn.mkdir(charters, "p")
		vim.fn.writefile({
			"[ ] first task #01951111-0000-7000-8000-000000000051",
			"[ ] second task #01951111-0000-7000-8000-000000000052",
			"[ ] third task #01951111-0000-7000-8000-000000000053",
		}, charters .. "/home.actions")

		local original_cwd = vim.fn.getcwd()
		local original_notify = vim.notify
		vim.cmd("cd " .. vim.fn.fnameescape(root))
		local init_output = vim.fn.system({ "clearhead", "init" })
		assert.are.equal(0, vim.v.shell_error, init_output)
		vim.notify = function() end

		view.open("default")
		wait_for(function()
			return #vim.fn.getqflist() == 3
		end, "initial list of three actions")

		vim.cmd("copen")
		vim.api.nvim_win_set_cursor(0, { 2, 0 })
		view.act("complete")
		wait_for(function()
			return #vim.fn.getqflist() == 2
		end, "view to settle after completion")

		local items = vim.fn.getqflist()
		assert.is_falsy(items[1].text:find("second task", 1, true))
		assert.is_falsy(items[2].text:find("second task", 1, true))
		assert.are.equal(2, vim.api.nvim_win_get_cursor(0)[1])

		local archive = assert(io.open(charters .. "/home.completed.actions", "r"))
		local content = archive:read("*a")
		archive:close()
		assert.is_truthy(content:find("second task", 1, true))

		vim.notify = original_notify
		vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
		vim.fn.delete(root, "rf")
	end)
end)
