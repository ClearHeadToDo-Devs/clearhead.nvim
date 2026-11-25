local assert = require("luassert")
local clearhead = require("clearhead")
local config = require("clearhead.config")

-- A stand-in `clearhead` that records its argv (one per line) and its cwd,
-- then answers the way the real `jot` does.
local FAKE_CLI = [[#!/bin/sh
printf '%s\n' "$@" > "$0.args"
pwd > "$0.cwd"
echo "Jotted to 019f733d-45c2-7dd2-91dc-8631f33c6b77 (charters/.work.json)"
]]

describe("clearhead.jot", function()
	local original_bin
	local root, script, notified

	local function lines(suffix)
		vim.wait(2000, function()
			return vim.fn.filereadable(script .. suffix) == 1
		end)
		return vim.fn.readfile(script .. suffix)
	end

	-- Wait for the CLI's reply, so it never lands in the next test.
	local function settle()
		vim.wait(2000, function()
			return #notified > 0
		end)
	end

	before_each(function()
		root = vim.uv.fs_realpath(vim.fn.tempname():match("^(.*)/")) .. "/jot-" .. vim.fn.localtime() .. math.random(1e6)
		vim.fn.mkdir(root .. "/.clearhead/charters", "p")
		vim.fn.writefile({ "# Work" }, root .. "/.clearhead/charters/work.md")
		vim.fn.writefile({ "[ ] Ship" }, root .. "/.clearhead/charters/work.actions")
		script = root .. "/fake-clearhead"
		vim.fn.writefile(vim.split(FAKE_CLI, "\n", { plain = true }), script)
		vim.fn.setfperm(script, "rwx------")

		original_bin = config.get_bin_path
		config.get_bin_path = function()
			return script
		end
		notified = {}
		stub(vim, "notify", function(msg)
			notified[#notified + 1] = msg
		end)
	end)

	after_each(function()
		config.get_bin_path = original_bin
		vim.notify:revert()
		vim.cmd("silent! %bwipeout!")
		vim.fn.delete(root, "rf")
	end)

	it("defaults the charter to the current buffer's and runs from its project", function()
		vim.cmd("edit " .. vim.fn.fnameescape(root .. "/.clearhead/charters/work.actions"))
		clearhead.jot("--looks like a flag")

		assert.are.same({ "jot", "charter", "work", "--", "--looks like a flag" }, lines(".args"))
		assert.are.same({ root }, lines(".cwd"))
		vim.wait(2000, function()
			return #notified > 0
		end)
		assert.are.same({ "Jotted to 019f733d-45c2-7dd2-91dc-8631f33c6b77 (charters/.work.json)" }, notified)
	end)

	it("jots on the charter from its document as from its actions file", function()
		vim.cmd("edit " .. vim.fn.fnameescape(root .. "/.clearhead/charters/work.md"))
		clearhead.jot("from the document")
		assert.are.same({ "jot", "charter", "work", "--", "from the document" }, lines(".args"))
		assert.are.same({ root }, lines(".cwd"))
		settle()
	end)

	it("asks for the text when given none, and jots nothing on an empty answer", function()
		vim.cmd("edit " .. vim.fn.fnameescape(root .. "/.clearhead/charters/work.actions"))
		local answer = "   "
		stub(vim.ui, "input", function(_, on_confirm)
			on_confirm(answer)
		end)
		clearhead.jot()
		vim.wait(200)
		assert.are.equal(0, vim.fn.filereadable(script .. ".args"))

		answer = "typed"
		clearhead.jot()
		vim.ui.input:revert()
		assert.are.same({ "jot", "charter", "work", "--", "typed" }, lines(".args"))
		settle()
	end)

	describe("on the action under the cursor", function()
		local original_id

		before_each(function()
			original_id = clearhead.action_id_under_cursor
		end)

		after_each(function()
			clearhead.action_id_under_cursor = original_id
		end)

		it("jots on its id from its workspace", function()
			vim.cmd("edit " .. vim.fn.fnameescape(root .. "/.clearhead/charters/work.actions"))
			clearhead.action_id_under_cursor = function()
				return "019f733d-45c2-7dd2-91dc-8631f33c6b77"
			end
			clearhead.jot_action("--a note")
			assert.are.same({ "jot", "019f733d-45c2-7dd2-91dc-8631f33c6b77", "--", "--a note" }, lines(".args"))
			assert.are.same({ root }, lines(".cwd"))
			settle()
		end)

		it("warns and asks for nothing when no action is under the cursor", function()
			clearhead.action_id_under_cursor = function()
				return nil
			end
			stub(vim.ui, "input")
			clearhead.jot_action()
			assert.stub(vim.ui.input).was_not_called()
			vim.ui.input:revert()
			assert.are.equal(1, #notified)
			assert.is_truthy(notified[1]:find("no action under the cursor", 1, true))
		end)
	end)

	it("lets an explicit charter win, and refuses outside a charter without one", function()
		vim.cmd("edit " .. vim.fn.fnameescape(root .. "/.clearhead/charters/work.actions"))
		clearhead.jot("note", { charter = "other" })
		assert.are.same({ "jot", "charter", "other", "--", "note" }, lines(".args"))
		vim.wait(2000, function()
			return #notified > 0
		end)

		notified = {}
		vim.fn.delete(script .. ".args")
		vim.cmd("enew")
		clearhead.jot("note")
		vim.wait(200)
		assert.are.equal(0, vim.fn.filereadable(script .. ".args"))
		assert.are.equal(1, #notified)
		assert.is_truthy(notified[1]:find("name a charter", 1, true))
	end)
end)
