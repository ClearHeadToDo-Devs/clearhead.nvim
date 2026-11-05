local clearhead = require("clearhead")

describe("habit_reader_conformance", function()
	it("removes the complete Habit suffix for root, flat and directory charter stems", function()
		local tmp = vim.fn.tempname() .. "/sample-project"
		vim.fn.mkdir(tmp .. "/.clearhead/charters/work", "p")
		local stem = clearhead._testing["charter-stem"]
		assert.are.equal("sample-project", stem(tmp .. "/.clearhead/charters/next.habits.actions"))
		assert.are.equal("review", stem(tmp .. "/.clearhead/charters/review.habits.actions"))
		assert.are.equal("work", stem(tmp .. "/.clearhead/charters/work/next.habits.actions"))
		vim.fn.delete(tmp, "rf")
	end)

	it("excludes Habit, terminal, template and archived files from live pickers", function()
		local live = clearhead._testing["live-action-file"]
		assert.is_true(live("/workspace/charters/work.actions"))
		for _, path in ipairs({
			"/workspace/charters/work.habits.actions",
			"/workspace/charters/work.completed.actions",
			"/workspace/charters/work.upcoming.actions",
			"/workspace/charters/templates/named.actions",
			"/workspace/archive/work.actions",
		}) do
			assert.is_false(not not live(path), path)
		end
	end)

	it("does not sweep Habits or their template children on save", function()
		local path = vim.fn.tempname() .. ".habits.actions"
		vim.cmd("edit " .. vim.fn.fnameescape(path))
		local old_system = vim.system
		local calls = 0
		vim.system = function() calls = calls + 1 end
		local ok, err = pcall(clearhead.archive_saved, vim.api.nvim_get_current_buf())
		vim.system = old_system
		vim.cmd("bwipeout!")
		assert.is_true(ok, err)
		assert.are.equal(0, calls)
	end)

	it("routes explicit Habit archival to its charter, not the Action sweep", function()
		local config = require("clearhead.config")
		local old_bin, old_jobstart = config.get_bin_path, vim.fn.jobstart
		local path = vim.fn.tempname() .. ".habits.actions"
		vim.cmd("edit " .. vim.fn.fnameescape(path))
		config.get_bin_path = function() return "clearhead" end
		local command
		vim.fn.jobstart = function(cmd) command = cmd; return 1 end
		local ok, err = pcall(clearhead.archive, vim.api.nvim_get_current_buf())
		config.get_bin_path, vim.fn.jobstart = old_bin, old_jobstart
		vim.cmd("bwipeout!")
		vim.fn.delete(path)
		assert.is_true(ok, err)
		assert.are.same({ "clearhead", "archive", "charter", "--file", path }, command)
	end)
end)
