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
		local tmp = vim.fn.tempname()
		local workspace = tmp .. "/.clearhead"
		vim.fn.mkdir(workspace .. "/charters", "p")
		assert.is_true(live(workspace .. "/charters/work.actions"))
		for _, path in ipairs({
			"charters/work.habits.actions",
			"charters/work.completed.actions",
			"charters/work.upcoming.actions",
			"templates/named.actions",
			"archive/work.actions",
		}) do
			assert.is_false(not not live(workspace .. "/" .. path), path)
		end
		vim.fn.delete(tmp, "rf")
	end)

	it("keeps parent role names and directory-form charters live", function()
		local live = clearhead._testing["live-action-file"]
		for _, parent in ipairs({ "archive", "templates", "charters" }) do
			local tmp = vim.fn.tempname() .. "/" .. parent .. "/ws"
			local root = tmp .. "/.clearhead/charters"
			vim.fn.mkdir(root .. "/archive", "p")
			vim.fn.writefile({ "[ ] Task" }, root .. "/home.actions")
			vim.fn.writefile({ "[ ] Task" }, root .. "/archive/next.actions")
			assert.is_true(not not live(root .. "/home.actions"))
			assert.is_true(not not live(root .. "/archive/next.actions"))
			for _, role in ipairs({ "templates", "archive" }) do
				local path = tmp .. "/.clearhead/" .. role .. "/x.actions"
				vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
				vim.fn.writefile({ "[ ] Not executable" }, path)
				assert.is_false(not not live(path), path)
			end
			local files = clearhead._testing["find-charter-files"](root, function(name) return name:match("%.actions$") end)
			assert.are.equal(2, #files)
			vim.fn.delete(tmp, "rf")
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
