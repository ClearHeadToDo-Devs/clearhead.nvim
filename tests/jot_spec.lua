local assert = require("luassert")
local clearhead = require("clearhead")
local config = require("clearhead.config")

-- A stand-in `clearhead` that records its argv (one per line) and its cwd,
-- then answers the way the real `jot` does.
local FAKE_CLI = [[#!/bin/sh
printf '%s\n' "$@" > "$0.args"
pwd > "$0.cwd"
echo "Jotted to 'Work' (work.md)"
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

		assert.are.same({ "jot", "--charter", "work", "--", "--looks like a flag" }, lines(".args"))
		assert.are.same({ root }, lines(".cwd"))
		vim.wait(2000, function()
			return #notified > 0
		end)
		assert.are.same({ "Jotted to 'Work' (work.md)" }, notified)
	end)

	it("lets an explicit charter win, and leaves it to the CLI outside a charter", function()
		vim.cmd("edit " .. vim.fn.fnameescape(root .. "/.clearhead/charters/work.actions"))
		clearhead.jot("note", { charter = "other" })
		assert.are.same({ "jot", "--charter", "other", "--", "note" }, lines(".args"))

		vim.fn.delete(script .. ".args")
		vim.cmd("enew")
		clearhead.jot("note")
		assert.are.same({ "jot", "--", "note" }, lines(".args"))
	end)

	it("refuses to write under an unsaved charter document", function()
		vim.cmd("edit " .. vim.fn.fnameescape(root .. "/.clearhead/charters/work.md"))
		vim.api.nvim_buf_set_lines(0, -1, -1, false, { "unsaved" })
		clearhead.jot("note")

		vim.wait(200)
		assert.are.equal(0, vim.fn.filereadable(script .. ".args"))
		assert.is_truthy(notified[1]:find("save", 1, true))
	end)
end)
