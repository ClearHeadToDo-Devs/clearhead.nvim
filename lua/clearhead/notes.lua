--- An action's notes, read from `clearhead show notes --json` and drawn as
--- prose: a peek float by default (like LSP hover: it closes when the cursor
--- moves, and asking again enters it), with `s` to keep them in a split.
local M = {}

local config = require("clearhead.config")

local FOCUS_ID = "clearhead-notes"

--- Noon of an `at` timestamp's own calendar day, as an os.time value, so
--- day differences ignore time zones and daylight saving.
local function day_of(at)
	local y, m, d = at:match("^(%d+)-(%d+)-(%d+)")
	return y and os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
end

--- "today", "yesterday" or "N days ago", from `at`'s date to `today`'s.
local function ago(day, today)
	local days = math.floor((today - day) / 86400 + 0.5)
	if days <= 0 then
		return "today"
	elseif days == 1 then
		return "yesterday"
	end
	return days .. " days ago"
end

--- Markdown lines for a list of notes ({at, by, text}), oldest first so the
--- newest is last: a header naming who wrote it and when, then the text.
--- `now` (an os.time value) is for tests; it defaults to the clock.
M.render = function(notes, now)
	local today = day_of(os.date("%Y-%m-%d", now or os.time()))
	local lines = {}
	for index, note in ipairs(notes) do
		if index > 1 then
			lines[#lines + 1] = ""
		end
		local day = day_of(note.at or "")
		local when = day
				and ("%s, %s at %s"):format(ago(day, today), os.date("%a %d %b %Y", day), note.at:match("T(%d+:%d+)") or "")
			or (note.at or "undated")
		lines[#lines + 1] = ("**%s** · %s"):format(note.by or "someone", when)
		vim.list_extend(lines, vim.split(note.text or "", "\n", { plain = true }))
	end
	return lines
end

local function open_split(id, lines)
	local name = "clearhead://notes/" .. id
	local existing = vim.fn.bufnr(name)
	if existing ~= -1 then
		vim.api.nvim_buf_delete(existing, { force = true })
	end
	vim.cmd("botright new")
	local bufnr = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_name(bufnr, name)
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].swapfile = false
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modifiable = false
	vim.bo[bufnr].filetype = "markdown"
	vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = bufnr, nowait = true, desc = "Close notes" })
end

local function open_float(id, lines)
	local bufnr = vim.lsp.util.open_floating_preview(lines, "markdown", {
		focus_id = FOCUS_ID,
		border = "rounded",
		title = " notes ",
		max_width = 80,
	})
	vim.keymap.set("n", "s", function()
		vim.cmd("close")
		open_split(id, lines)
	end, { buffer = bufnr, nowait = true, desc = "Open notes in a split" })
end

--- The workspace of the action under the cursor, for running the CLI there:
--- the current buffer's, or a quickfix entry's file's. Else the cwd.
M.cursor_cwd = function()
	local path = vim.api.nvim_buf_get_name(0)
	if vim.bo.buftype == "quickfix" then
		local entry = vim.fn.getqflist()[vim.fn.line(".")]
		path = entry and entry.bufnr > 0 and vim.api.nvim_buf_get_name(entry.bufnr) or ""
	end
	return (path ~= "" and require("clearhead").workspace_root(path)) or vim.fn.getcwd()
end

--- Show the notes of `target` (an id or alias), else of the action under the
--- cursor. `opts.split` opens the split straight away; `opts.what` names the
--- entity in the empty message (default "action"). The CLI runs from the
--- action's own workspace, so a quickfix entry from another workspace works.
M.show = function(target, opts)
	opts = opts or {}
	local ch = require("clearhead")
	local id = target or ch.action_id_under_cursor()
	if not id then
		vim.notify("clearhead: no action under the cursor.", vim.log.levels.WARN)
		return
	end
	local bin = config.get_bin_path()
	if not bin then
		vim.notify("clearhead binary not found.", vim.log.levels.ERROR)
		return
	end
	local cwd = M.cursor_cwd()
	vim.system({ bin, "show", "notes", id, "--json" }, { cwd = cwd, text = true }, function(done)
		vim.schedule(function()
			if done.code ~= 0 then
				vim.notify("clearhead show notes failed.\n" .. vim.trim(done.stderr or ""), vim.log.levels.ERROR)
				return
			end
			local ok, notes = pcall(vim.json.decode, done.stdout or "")
			if not ok or type(notes) ~= "table" then
				vim.notify("clearhead show notes: unreadable output.", vim.log.levels.ERROR)
				return
			end
			if #notes == 0 then
				vim.notify(("clearhead: no notes on this %s yet."):format(opts.what or "action"))
				return
			end
			local lines = M.render(notes)
			if opts.split then
				open_split(id, lines)
			else
				open_float(id, lines)
			end
		end)
	end)
end

return M
