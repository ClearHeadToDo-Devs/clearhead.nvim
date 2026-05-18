local config = require("clearhead.config")
local lsp = require("clearhead.lsp")
local actions = require("clearhead.actions")

local M = {}

-- Re-export the actions API so callers only need to require("clearhead").
M.cycle_state = actions.cycle_state
M.set_state = actions.set_state
M.set_state_tree = actions.set_state_tree
M.smart_new_action = actions.smart_new_action
M.get_status = actions.get_status
M.indent_action = actions.indent_action
M.dedent_action = actions.dedent_action

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

local function on_output(prefix)
	return function(_, data)
		if not (data and #data > 0) then
			return
		end
		local msg = table.concat(data, "\n")
		if msg == "" or msg:find("^%s*$") then
			return
		end
		if prefix then
			vim.notify(prefix .. msg, vim.log.levels.ERROR)
		else
			vim.notify(msg)
		end
	end
end

--- Open a file path in the given window without changing global window focus.
--- winnr: window handle (0 = current window)
--- path: absolute file path
local function open_file_in_win(winnr, path)
	local buf = vim.fn.bufadd(path)
	-- Do not call bufload manually — nvim_win_set_buf will trigger the load
	-- sequence in the correct context, avoiding re-entrant autocmd firing.
	vim.api.nvim_win_set_buf(winnr, buf)
end

--- Return list of { charters=path, label=scope } for global workspace +
--- nearest project .clearhead/ (walk up from cwd). Deduped.
local function collect_workspace_roots()
	local roots = {}
	local seen = {}

	local function add(charters_path, label)
		if not seen[charters_path] then
			seen[charters_path] = true
			roots[#roots + 1] = { charters = charters_path, label = label }
		end
	end

	-- Global workspace
	local data_dir = config.expand_path(config.values.data_dir)
	if data_dir and data_dir ~= "" then
		add(data_dir .. "/charters", "~")
	end

	-- Nearest project workspace: walk up from cwd
	local dir = vim.fn.getcwd()
	while true do
		local candidate = dir .. "/.clearhead"
		local stat = vim.uv.fs_stat(candidate)
		if stat and stat.type == "directory" then
			add(candidate .. "/charters", vim.fn.fnamemodify(dir, ":t"))
			break
		end
		local parent = vim.fn.fnamemodify(dir, ":h")
		if parent == dir then
			break
		end
		dir = parent
	end

	return roots
end

--- Derive a human-readable charter name from a file path inside charters/.
--- next.actions / README.md → parent directory name; everything else → stem.
local function charter_stem(path)
	local tail = vim.fn.fnamemodify(path, ":t")
	-- Directory-form charter files all use 'next' as the filename stem;
	-- the charter name is the parent directory.
	if tail == "next.actions"
		or tail == "next.completed.actions"
		or tail == "next.upcoming.actions"
		or tail == "README.md"
	then
		return vim.fn.fnamemodify(path, ":h:t")
	end
	local stem = vim.fn.fnamemodify(path, ":t:r")
	stem = stem:gsub("%.completed$", ""):gsub("%.upcoming$", "")
	return stem
end

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------

M.setup = function(opts)
	config.load(opts)

	local group = vim.api.nvim_create_augroup("clearhead", { clear = true })

	if config.values.nvim_format_on_save then
		vim.api.nvim_create_autocmd("BufWritePre", {
			pattern = "*.actions",
			group = group,
			callback = function(args)
				M.format(args.buf)
			end,
		})
	end

	vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
		pattern = "*.actions",
		group = group,
		callback = function()
			if vim.fn.mode() == "n" and vim.fn.bufname() ~= "" then
				vim.cmd("checktime")
			end
		end,
	})

	vim.api.nvim_create_autocmd("FileChangedShellPost", {
		pattern = "*.actions",
		group = group,
		callback = function()
			vim.notify("File updated from disk.", vim.log.levels.INFO)
		end,
	})

	vim.api.nvim_create_autocmd("FileType", {
		pattern = "actions",
		group = group,
		callback = function(args)
			vim.opt_local.autoread = true
			vim.opt_local.conceallevel = 2
			vim.opt_local.concealcursor = "nc"
			lsp.attach(args.buf)

			if config.values.nvim_default_mappings then
				local function map(key, fn, desc)
					vim.keymap.set("n", key, fn, { buffer = true, desc = desc })
				end
				-- State manipulation — closures supply current buffer/cursor at call time.
				map("<localleader><space>", function()
					M.cycle_state(0, vim.fn.line(".") - 1)
				end, "Cycle action state")
				map("<localleader>x", function()
					M.set_state(0, vim.fn.line(".") - 1, "x")
				end, "Set state to Completed")
				map("<localleader>X", function()
					M.set_state_tree(0, vim.fn.line(".") - 1, "x")
				end, "Close action and all children")
				map("<localleader>-", function()
					M.set_state(0, vim.fn.line(".") - 1, "-")
				end, "Set state to In Progress")
				map("<localleader>=", function()
					M.set_state(0, vim.fn.line(".") - 1, "=")
				end, "Set state to Blocked")
				map("<localleader>_", function()
					M.set_state(0, vim.fn.line(".") - 1, "_")
				end, "Set state to Cancelled")
				map("<localleader><bs>", function()
					M.set_state(0, vim.fn.line(".") - 1, " ")
				end, "Set state to Not Started")
				-- File operations
				map("<localleader>f", M.format, "Format action file")
				map("<localleader>a", M.archive, "Archive completed actions")
				map("<localleader>A", M.archive_charter, "Archive current charter")
				map("<localleader>o", function()
					M.smart_new_action(0, vim.fn.line(".") - 1)
				end, "New action below")
				map(">>", function()
					M.indent_action(0, vim.fn.line(".") - 1)
				end, "Increase action depth")
				map("<<", function()
					M.dedent_action(0, vim.fn.line(".") - 1)
				end, "Decrease action depth")
				-- Navigation
				map("<localleader>i", function()
					M.open_inbox(0)
				end, "Open inbox")
				map("<localleader>p", function()
					M.open_workspace(0)
				end, "Browse workspace")
				map("<localleader>P", function()
					M.open_project_root(0)
				end, "Open project root")
				map("<localleader>s", M.pick_action_file, "Pick active action file")
				map("<localleader>S", M.pick_charter_doc, "Pick charter document")
			end
		end,
	})

	vim.api.nvim_create_user_command("ClearheadInbox", function()
		M.open_inbox(0)
	end, {})
	vim.api.nvim_create_user_command("ClearheadWorkspace", function()
		M.open_workspace(0)
	end, {})
	vim.api.nvim_create_user_command("ClearheadProjectRoot", function()
		M.open_project_root(0)
	end, {})
	vim.api.nvim_create_user_command("ClearheadDiff", function()
		vim.cmd("vertical diffsplit %")
	end, {})
	vim.api.nvim_create_user_command("ClearheadArchiveWorkspace", function()
		M.archive_workspace()
	end, {})
	vim.api.nvim_create_user_command("ClearheadPickActions", function()
		M.pick_action_file()
	end, {})
	vim.api.nvim_create_user_command("ClearheadPickCharters", function()
		M.pick_charter_doc()
	end, {})
end

-- ---------------------------------------------------------------------------
-- File operations
-- ---------------------------------------------------------------------------

M.archive = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local clients = vim.lsp.get_clients({ name = "clearhead-lsp", bufnr = bufnr })
	local client = clients[1]
	if client then
		client:request("workspace/executeCommand", {
			command = "clearhead/archive",
			arguments = { vim.uri_from_bufnr(bufnr) },
		}, function(err)
			if err then
				vim.schedule(function()
					vim.notify("Archive failed: " .. (err.message or "unknown error"), vim.log.levels.ERROR)
				end)
				return
			end
			vim.schedule(function()
				vim.notify("Archived completed actions.")
			end)
		end, bufnr)
		return
	end

	local filename = vim.api.nvim_buf_get_name(bufnr)
	local bin = config.get_bin_path()
	if filename == "" or not bin then
		vim.notify("Cannot archive: buffer has no file or CLI not found.", vim.log.levels.ERROR)
		return
	end

	-- .completed.actions files hold already-closed actions waiting to be swept
	-- into archive.ttl. Passing them to `archive actions --file` would call
	-- completed_acts_path() on the path, producing a .completed.completed.actions
	-- file. Route to `archive charter <name>` instead so they go to archive.ttl.
	local tail = vim.fn.fnamemodify(filename, ":t")
	if tail:match("%.completed%.actions$") then
		local name = charter_stem(filename)
		vim.fn.jobstart({ bin, "archive", "charter", name }, {
			on_exit = function(_, exit_code)
				vim.schedule(function()
					if exit_code == 0 then
						vim.notify("Charter '" .. name .. "' archived to archive.ttl.")
					else
						vim.notify(
							"Charter '" .. name .. "' must have 'state: Closed' in its .md file. "
								.. "Set it, then use <localleader>A.",
							vim.log.levels.WARN
						)
					end
				end)
			end,
			on_stdout = on_output(nil),
			on_stderr = on_output("Archive charter error: "),
		})
		return
	end

	vim.api.nvim_buf_call(bufnr, function()
		vim.cmd("write")
	end)
	vim.fn.jobstart({ bin, "archive", "actions", "--file", filename }, {
		on_exit = function(_, exit_code)
			if exit_code == 0 then
				vim.schedule(function()
					vim.api.nvim_buf_call(bufnr, function()
						vim.api.nvim_command("edit!")
					end)
					vim.notify("Archived completed actions.")
				end)
			else
				vim.notify("Archive failed.", vim.log.levels.ERROR)
			end
		end,
		on_stdout = on_output(nil),
		on_stderr = on_output("Archive error: "),
	})
end

--- Archive the current charter (requires state: Closed in its frontmatter).
--- Infers the charter from the currently open buffer's file path.
--- Pass force=true to sweep even if open actions remain.
M.archive_charter = function(opts)
	opts = opts or {}
	local bin = config.get_bin_path()
	if not bin then
		vim.notify("clearhead binary not found.", vim.log.levels.ERROR)
		return
	end

	-- Infer charter name from the current buffer path.
	local buf_path = vim.api.nvim_buf_get_name(0)
	local charter_name = nil
	if buf_path ~= "" then
		-- Strip the file extension and use the stem as the charter query.
		-- For directory-form charters (health/next.actions) use the parent dir name.
		local filename = vim.fn.fnamemodify(buf_path, ":t")
		if filename == "next.actions" then
			charter_name = vim.fn.fnamemodify(buf_path, ":h:t")
		else
			charter_name = vim.fn.fnamemodify(buf_path, ":t:r")
			-- Strip .completed / .upcoming suffixes
			charter_name = charter_name:gsub("%.completed$", ""):gsub("%.upcoming$", "")
		end
	end

	if not charter_name or charter_name == "" then
		vim.notify("Cannot infer charter from current buffer.", vim.log.levels.ERROR)
		return
	end

	local cmd = { bin, "archive", "charter", charter_name }
	if opts.force then
		table.insert(cmd, "--force")
	end
	if opts.dry_run then
		table.insert(cmd, "--dry-run")
	end

	vim.fn.jobstart(cmd, {
		on_exit = function(_, exit_code)
			vim.schedule(function()
				if exit_code == 0 then
					vim.notify("Charter '" .. charter_name .. "' archived.")
				else
					vim.notify("Archive charter failed (exit " .. exit_code .. ").", vim.log.levels.ERROR)
				end
			end)
		end,
		on_stdout = on_output(nil),
		on_stderr = on_output("Archive charter error: "),
	})
end

--- Archive all charters whose frontmatter carries `state: Closed`.
--- This is the workspace-wide sweep hotkey.
M.archive_workspace = function(opts)
	opts = opts or {}
	local bin = config.get_bin_path()
	if not bin then
		vim.notify("clearhead binary not found.", vim.log.levels.ERROR)
		return
	end

	local cmd = { bin, "archive", "charter", "--closed" }
	if opts.force then
		table.insert(cmd, "--force")
	end
	if opts.dry_run then
		table.insert(cmd, "--dry-run")
	end

	vim.fn.jobstart(cmd, {
		on_exit = function(_, exit_code)
			vim.schedule(function()
				if exit_code == 0 then
					vim.notify("Workspace archive complete.")
				else
					vim.notify("Workspace archive failed (exit " .. exit_code .. ").", vim.log.levels.ERROR)
				end
			end)
		end,
		on_stdout = on_output(nil),
		on_stderr = on_output("Archive workspace error: "),
	})
end

M.format = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local attached = vim.lsp.get_clients({ name = "clearhead-lsp", bufnr = bufnr })

	if #attached > 0 then
		vim.lsp.buf.format({ name = "clearhead-lsp", bufnr = bufnr })
		return
	end

	if #vim.lsp.get_clients({ name = "clearhead-lsp" }) > 0 then
		lsp.attach(bufnr)
		vim.schedule(function()
			vim.lsp.buf.format({ name = "clearhead-lsp", bufnr = bufnr })
		end)
		return
	end

	if config.values.nvim_auto_normalize then
		M.normalize(bufnr)
	end
end

M.normalize = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local filename = vim.api.nvim_buf_get_name(bufnr)
	local bin = config.get_bin_path()
	if filename == "" or not bin then
		return
	end

	vim.fn.jobstart({ bin, "normalize", "file", filename, "--write" }, {
		on_exit = function(_, exit_code)
			if exit_code == 0 then
				vim.schedule(function()
					vim.api.nvim_buf_call(bufnr, function()
						vim.api.nvim_command("checktime")
					end)
				end)
			end
		end,
		on_stderr = on_output("clearhead normalize error: "),
	})
end

-- ---------------------------------------------------------------------------
-- Navigation
-- ---------------------------------------------------------------------------

--- Open the inbox file in the given window.
--- winnr: window handle (0 = current window)
M.open_inbox = function(winnr)
	local path
	if config.values.nvim_inbox_file and config.values.nvim_inbox_file ~= "" then
		path = config.expand_path(config.values.nvim_inbox_file)
	else
		path = config.expand_path(config.values.data_dir) .. "/charters/" .. config.values.default_file
	end
	open_file_in_win(winnr, path)
end

--- Open the workspace data directory in the given window.
--- winnr: window handle (0 = current window)
M.open_workspace = function(winnr)
	open_file_in_win(winnr, config.expand_path(config.values.data_dir))
end

--- Walk upward from the current buffer's directory to find the nearest
--- .clearhead/ subdirectory, then open next.actions inside it.
--- Falls back to open_inbox if no project root is found.
--- winnr: window handle (0 = current window)
M.open_project_root = function(winnr)
	local buf_path = vim.api.nvim_buf_get_name(
		vim.api.nvim_win_get_buf(winnr == 0 and vim.api.nvim_get_current_win() or winnr)
	)
	local start_dir = buf_path ~= "" and vim.fn.fnamemodify(buf_path, ":h") or vim.fn.getcwd()

	local dir = start_dir
	while true do
		local candidate = dir .. "/.clearhead"
		local stat = vim.uv.fs_stat(candidate)
		if stat and stat.type == "directory" then
			open_file_in_win(winnr, candidate .. "/charters/next.actions")
			return
		end
		local parent = vim.fn.fnamemodify(dir, ":h")
		if parent == dir then
			break
		end
		dir = parent
	end

	vim.notify("No .clearhead/ directory found, opening inbox instead.", vim.log.levels.WARN)
	M.open_inbox(winnr)
end

--- Pick an active action file across all workspace roots using vim.ui.select.
--- Active = *.actions excluding *.completed.actions and *.upcoming.actions.
--- Integrates with telescope/fzf-lua/snacks automatically via vim.ui.select.
M.pick_action_file = function()
	local roots = collect_workspace_roots()
	local items = {}
	local multi_scope = #roots > 1

	for _, root in ipairs(roots) do
		local files = vim.fn.glob(root.charters .. "/*.actions", false, true)
		local subfiles = vim.fn.glob(root.charters .. "/*/*.actions", false, true)
		vim.list_extend(files, subfiles)

		for _, path in ipairs(files) do
			local tail = vim.fn.fnamemodify(path, ":t")
			if not tail:match("%.completed%.actions$") and not tail:match("%.upcoming%.actions$") then
				items[#items + 1] = {
					path = path,
					name = charter_stem(path),
					scope = root.label,
					multi_scope = multi_scope,
				}
			end
		end
	end

	if #items == 0 then
		vim.notify("No active action files found.", vim.log.levels.WARN)
		return
	end

	table.sort(items, function(a, b)
		if a.scope ~= b.scope then
			return a.scope < b.scope
		end
		return a.name < b.name
	end)

	vim.ui.select(items, {
		prompt = "Action file: ",
		format_item = function(item)
			if item.multi_scope then
				return "[" .. item.scope .. "] " .. item.name
			end
			return item.name
		end,
	}, function(choice)
		if choice then
			open_file_in_win(0, choice.path)
		end
	end)
end

--- Pick a markdown charter document across all workspace roots using vim.ui.select.
--- Matches *.md at the top level and */README.md for directory-form charters.
M.pick_charter_doc = function()
	local roots = collect_workspace_roots()
	local items = {}
	local multi_scope = #roots > 1

	for _, root in ipairs(roots) do
		local files = vim.fn.glob(root.charters .. "/*.md", false, true)
		local subfiles = vim.fn.glob(root.charters .. "/*/*.md", false, true)
		vim.list_extend(files, subfiles)

		for _, path in ipairs(files) do
			items[#items + 1] = {
				path = path,
				name = charter_stem(path),
				scope = root.label,
				multi_scope = multi_scope,
			}
		end
	end

	if #items == 0 then
		vim.notify("No charter documents found.", vim.log.levels.WARN)
		return
	end

	table.sort(items, function(a, b)
		if a.scope ~= b.scope then
			return a.scope < b.scope
		end
		return a.name < b.name
	end)

	vim.ui.select(items, {
		prompt = "Charter doc: ",
		format_item = function(item)
			if item.multi_scope then
				return "[" .. item.scope .. "] " .. item.name
			end
			return item.name
		end,
	}, function(choice)
		if choice then
			open_file_in_win(0, choice.path)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- conform.nvim integration helper
-- ---------------------------------------------------------------------------

M.get_conform_opts = function()
	return {
		formatters_by_ft = { actions = { "clearhead" } },
		formatters = {
			clearhead = {
				command = "clearhead",
				args = { "format", "file", "$FILENAME" },
				stdin = false,
			},
		},
	}
end

-- ---------------------------------------------------------------------------
-- Testing hooks
-- ---------------------------------------------------------------------------

M._testing = {
	["load-config-internal"] = function(opts)
		return { config = config.load(opts) }
	end,
}

return M
