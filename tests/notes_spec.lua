local assert = require("luassert")
local config = require("clearhead.config")
local notes = require("clearhead.notes")

describe("notes", function()
	-- Noon on Wed 25 Nov 2026, local time.
	local NOW = os.time({ year = 2026, month = 11, day = 25, hour = 12 })

	describe("render", function()
		it("writes each note as who and when, then its text, oldest first", function()
			local lines = notes.render({
				{ at = "2026-11-23T09:05:00-08:00", by = "Darrion", text = "first line\nsecond line" },
				{ at = "2026-11-25T01:33:00+00:00", by = "agent:steward", text = "newest" },
			}, NOW)
			assert.are.same({
				"**Darrion** · 2 days ago, Mon 23 Nov 2026 at 09:05",
				"first line",
				"second line",
				"",
				"**agent:steward** · today, Wed 25 Nov 2026 at 01:33",
				"newest",
			}, lines)
		end)

		it("says yesterday, and names no one when the note has no author", function()
			local lines = notes.render({ { at = "2026-11-24T22:00:00+00:00", text = "x" } }, NOW)
			assert.are.equal("**someone** · yesterday, Tue 24 Nov 2026 at 22:00", lines[1])
		end)
	end)

	describe("show", function()
		local original_bin, root, script, notified

		local function fake_cli(json)
			script = root .. "/fake-clearhead"
			vim.fn.writefile({
				"#!/bin/sh",
				[[printf '%s\n' "$@" > "$0.args"]],
				"cat <<'EOF'",
				json,
				"EOF",
			}, script)
			vim.fn.setfperm(script, "rwx------")
		end

		before_each(function()
			root = vim.fn.tempname()
			vim.fn.mkdir(root, "p")
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
			vim.cmd("silent! only")
			vim.cmd("silent! %bwipeout!")
			vim.fn.delete(root, "rf")
		end)

		local function floats()
			return vim.tbl_filter(function(win)
				return vim.api.nvim_win_get_config(win).relative ~= ""
			end, vim.api.nvim_list_wins())
		end

		local NOTE = [[[{"at":"2026-11-24T07:26:00+00:00","by":"Darrion","text":"landed"}] ]]

		it("asks the CLI for the target's notes as JSON and peeks at them in a float", function()
			fake_cli(NOTE)
			notes.show("logs-in-sidecar")
			vim.wait(2000, function()
				return #floats() > 0
			end)
			assert.are.same({ "show", "notes", "logs-in-sidecar", "--json" }, vim.fn.readfile(script .. ".args"))
			local float = floats()[1]
			assert.is_not_nil(float)
			local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(float), 0, -1, false), "\n")
			assert.matches("Darrion", text)
			assert.matches("landed", text)
		end)

		it("opens a split instead when asked", function()
			fake_cli(NOTE)
			notes.show("abc", { split = true })
			vim.wait(2000, function()
				return vim.fn.bufnr("clearhead://notes/abc") ~= -1
			end)
			local bufnr = vim.fn.bufnr("clearhead://notes/abc")
			assert.are_not.equal(-1, bufnr)
			assert.are.equal("markdown", vim.bo[bufnr].filetype)
			assert.is_false(vim.bo[bufnr].modifiable)
			assert.are.same({}, floats())
		end)

		it("peeks at the notes of the charter whose file is open", function()
			fake_cli(NOTE)
			local charters = root .. "/.clearhead/charters"
			vim.fn.mkdir(charters, "p")
			vim.cmd.edit(charters .. "/deployment.md")
			require("clearhead").show_charter_notes()
			vim.wait(2000, function()
				return #floats() > 0
			end)
			assert.are.same({ "show", "notes", "deployment", "--json" }, vim.fn.readfile(script .. ".args"))
			assert.are.equal(1, #floats())
		end)

		it("refuses a file that is not a charter's", function()
			vim.cmd.edit(root .. "/elsewhere.md")
			require("clearhead").show_charter_notes()
			assert.are.same({ "clearhead: not a charter file." }, notified)
		end)

		it("says so instead of opening an empty float", function()
			fake_cli("[]")
			notes.show("abc")
			vim.wait(2000, function()
				return #notified > 0
			end)
			assert.are.same({ "clearhead: no notes on this action yet." }, notified)
			assert.are.same({}, floats())
		end)
	end)
end)
