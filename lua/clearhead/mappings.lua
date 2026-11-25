-- Every clearhead keymap is a <Plug>(clearhead-*) mapping: that name is the
-- public API (:h clearhead-mappings). Default keys are buffer-local maps onto
-- those names, skipped per action when the user already maps the <Plug>
-- anywhere (:h hasmapto()), so overriding one key needs one line.
local M = {}

local function ch()
	return require("clearhead")
end

local function line()
	return vim.fn.line(".") - 1
end

-- Action edits rewrite the current line, so they refuse to run outside an
-- .actions buffer; a global user mapping must not touch arbitrary files.
local function in_actions(fn)
	return function()
		if vim.bo.filetype ~= "actions" then
			vim.notify("clearhead: not an .actions buffer", vim.log.levels.WARN)
			return
		end
		fn()
	end
end

local function set(state)
	return in_actions(function()
		ch().set_state(0, line(), state)
	end)
end

-- Rows: { <Plug> suffix, default key (false = none), description, function }

M.actions = {
	{ "cycle-state", "<localleader><space>", "Cycle action state", in_actions(function()
		ch().cycle_state(0, line())
	end) },
	{ "complete", "<localleader>x", "Set state to Completed", set("x") },
	{ "complete-tree", "<localleader>X", "Complete target and open descendants", in_actions(function()
		ch().set_state_tree(0, line(), "x")
	end) },
	{ "in-progress", "<localleader>-", "Set state to In Progress", set("-") },
	{ "blocked", "<localleader>=", "Set state to Blocked", set("=") },
	{ "cancel", "<localleader>_", "Set state to Cancelled", set("_") },
	{ "reset", "<localleader><bs>", "Set state to Not Started", set(" ") },
	{ "format", "<localleader>f", "Format action file", in_actions(function()
		ch().format()
	end) },
	{ "archive", "<localleader>a", "Archive completed actions", in_actions(function()
		ch().archive()
	end) },
	{ "new-action", "<localleader>o", "New action below", in_actions(function()
		ch().smart_new_action(0, line())
	end) },
	{ "indent", ">>", "Increase action depth", in_actions(function()
		ch().indent_action(0, line())
	end) },
	{ "dedent", "<<", "Decrease action depth", in_actions(function()
		ch().dedent_action(0, line())
	end) },
	-- Not in_actions: a quickfix entry has an action under the cursor too.
	{ "notes", "<localleader>n", "Peek at the notes of the action under the cursor", function()
		ch().show_notes()
	end },
}

M.charter = {
	{ "archive-charter", "<localleader>A", "Archive current charter", function()
		ch().archive_charter()
	end },
	{ "close-charter", "<localleader>C", "Close current charter", function()
		ch().close_charter()
	end },
	{ "open-inbox", "<localleader>i", "Open default capture file", function()
		ch().open_inbox(0)
	end },
	{ "quick-add", "<localleader>q", "Quick-add actions to the capture file", function()
		ch().open_quick_add()
	end },
	{ "open-workspace", "<localleader>p", "Browse workspace", function()
		ch().open_workspace(0)
	end },
	{ "open-project", "<localleader>P", "Open project root", function()
		ch().open_project_root(0)
	end },
	{ "pick-actions", "<localleader>s", "Pick active action file", function()
		ch().pick_action_file()
	end },
	{ "pick-charters", "<localleader>S", "Pick charter document", function()
		ch().pick_charter_doc()
	end },
}

-- Quickfix is not our filetype, so these get no default keys. The functions
-- check the list is a clearhead view and warn otherwise.
M.quickfix = {
	{ "entry-complete", false, "Complete action under cursor", function()
		ch().act_on_entry("complete")
	end },
	{ "entry-cancel", false, "Cancel action under cursor", function()
		ch().act_on_entry("cancel")
	end },
	{ "refresh-view", false, "Refresh clearhead view", function()
		ch().refresh_view()
	end },
}

M.plug = function(name)
	return "<Plug>(clearhead-" .. name .. ")"
end

M.define = function()
	for _, rows in ipairs({ M.actions, M.charter, M.quickfix }) do
		for _, row in ipairs(rows) do
			vim.keymap.set("n", M.plug(row[1]), row[4], { desc = row[3] })
		end
	end
end

-- hasmapto() sees global maps and the current buffer's, hence nvim_buf_call.
M.apply_defaults = function(bufnr, rows)
	vim.api.nvim_buf_call(bufnr, function()
		for _, row in ipairs(rows) do
			local plug = M.plug(row[1])
			if row[2] and vim.fn.hasmapto(plug, "n") == 0 then
				vim.keymap.set("n", row[2], plug, { buffer = bufnr, remap = true, desc = row[3] })
			end
		end
	end)
end

return M
