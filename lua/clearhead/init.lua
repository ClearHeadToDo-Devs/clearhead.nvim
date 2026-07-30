local config = require("clearhead.config")
local lsp = require("clearhead.lsp")
local actions = require("clearhead.actions")
local query = require("clearhead.query")
local view = require("clearhead.view")
local tree_view = require("clearhead.tree_view")
local graph_view = require("clearhead.graph_view")

local M = {}
local bootstrap_done = false
local config_loaded = false

local function ensure_config_loaded()
	if not config_loaded then
		config.load()
		config_loaded = true
	end
end

ensure_config_loaded()

-- Re-export the actions API so callers only need to require("clearhead").
M.cycle_state = actions.cycle_state
M.set_state = actions.set_state
M.set_state_tree = actions.set_state_tree
M.smart_new_action = actions.smart_new_action
M.get_status = actions.get_status
M.indent_action = actions.indent_action
M.dedent_action = actions.dedent_action
M.run_query = query.run_query
M.open_view = view.open
M.refresh_view = view.refresh
M.act_on_entry = view.act
M.open_tree = tree_view.open
M.refresh_tree = tree_view.refresh
M.open_graph = graph_view.open
M.refresh_graph = graph_view.refresh
M.preview_graph = graph_view.preview

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

--- Run a clearhead CLI command and notify on completion.
--- error_label is the human verb phrase used in failure messages, e.g. "Close charter".
--- cwd is optional; when provided the CLI subprocess is launched from that directory
--- so find_project_data_dir() walks up from the correct project root.
local function run_charter_cmd(cmd, success_msg, error_label, cwd)
	vim.fn.jobstart(cmd, {
		cwd = cwd,
		on_exit = function(_, exit_code)
			vim.schedule(function()
				if exit_code == 0 then
					vim.notify(success_msg)
				else
					vim.notify(error_label .. " failed (exit " .. exit_code .. ").", vim.log.levels.ERROR)
				end
			end)
		end,
		on_stdout = on_output(nil),
		on_stderr = on_output(error_label .. " error: "),
	})
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

local function is_directory(path)
	local stat = path and vim.uv.fs_stat(path) or nil
	return stat and stat.type == "directory"
end

--- Accept a workspace root, a project root containing .clearhead/, or a
--- charters/ directory and normalize it to the workspace root.
local function normalize_workspace_root(path)
	path = config.expand_path(path)
	if not (path and path ~= "") then
		return nil
	end
	if is_directory(path .. "/charters") then
		return path
	end
	if is_directory(path .. "/.clearhead/charters") then
		return path .. "/.clearhead"
	end
	if vim.fn.fnamemodify(path, ":t") == ".clearhead" and is_directory(path .. "/charters") then
		return path
	end
	if vim.fn.fnamemodify(path, ":t") == "charters" and is_directory(path) then
		return vim.fn.fnamemodify(path, ":h")
	end
	return nil
end

local function workspace_label(workspace_root)
	if vim.fn.fnamemodify(workspace_root, ":t") == ".clearhead" then
		return vim.fn.fnamemodify(workspace_root, ":h:t")
	end
	return vim.fn.fnamemodify(workspace_root, ":t")
end

local function add_workspace_root(roots, seen, workspace_root, label)
	workspace_root = normalize_workspace_root(workspace_root)
	if not workspace_root then
		return
	end

	local charters_path = workspace_root .. "/charters"
	if not seen[charters_path] then
		seen[charters_path] = true
		roots[#roots + 1] = { charters = charters_path, label = label or workspace_label(workspace_root) }
	end
end

local function collect_ancestor_workspaces(start_path, roots, seen, project_roots, project_seen)
	if not (start_path and start_path ~= "") then
		return
	end

	local stat = vim.uv.fs_stat(start_path)
	local dir = (stat and stat.type == "directory") and start_path or vim.fn.fnamemodify(start_path, ":h")
	while dir and dir ~= "" do
		local candidate = dir .. "/.clearhead"
		if is_directory(candidate) then
			add_workspace_root(roots, seen, candidate)
			if not project_seen[candidate] then
				project_seen[candidate] = true
				project_roots[#project_roots + 1] = candidate
			end
		end
		local parent = vim.fn.fnamemodify(dir, ":h")
		if parent == dir then
			break
		end
		dir = parent
	end
end

local function collect_child_project_workspaces(workspace_root, roots, seen)
	if vim.fn.fnamemodify(workspace_root, ":t") ~= ".clearhead" then
		return
	end

	local project_root = vim.fn.fnamemodify(workspace_root, ":h")
	for name, kind in vim.fs.dir(project_root) do
		if kind == "directory" and name ~= ".clearhead" and name:sub(1, 1) ~= "." then
			local candidate = project_root .. "/" .. name .. "/.clearhead"
			if is_directory(candidate) then
				add_workspace_root(roots, seen, candidate, name)
			end
		end
	end
end

local function current_picker_start(opts)
	opts = opts or {}
	if opts.current_file and opts.current_file ~= "" then
		return opts.current_file
	end
	local buf_path = vim.api.nvim_buf_get_name(0)
	if buf_path ~= "" then
		return buf_path
	end
	return opts.cwd or vim.fn.getcwd()
end

--- Return list of { charters=path, label=scope } for global workspace,
--- all ancestor project workspaces from the current buffer/cwd, direct child
--- repos inside any enclosing higher-order project workspace, and any
--- configured additional_workspaces. Deduped.
local function collect_workspace_roots(opts)
	opts = opts or {}
	local roots = {}
	local seen = {}
	local project_roots = {}
	local project_seen = {}

	local data_dir = normalize_workspace_root(config.values.data_dir)
	if data_dir then
		add_workspace_root(roots, seen, data_dir, "~")
	end

	local starts = { current_picker_start(opts), opts.cwd or vim.fn.getcwd() }
	local start_seen = {}
	for _, start in ipairs(starts) do
		if start and start ~= "" and not start_seen[start] then
			start_seen[start] = true
			collect_ancestor_workspaces(start, roots, seen, project_roots, project_seen)
		end
	end

	for _, workspace_root in ipairs(project_roots) do
		collect_child_project_workspaces(workspace_root, roots, seen)
	end

	for _, path in ipairs(config.values.additional_workspaces or {}) do
		add_workspace_root(roots, seen, path)
	end

	return roots
end

local function workspace_root_for_charter_path(path)
	if not (path and path ~= "") then
		return nil
	end

	local dir = vim.fn.fnamemodify(path, ":h")
	while dir and dir ~= "" do
		if vim.fn.fnamemodify(dir, ":t") == "charters" then
			local workspace_root = normalize_workspace_root(vim.fn.fnamemodify(dir, ":h"))
			if workspace_root and dir == workspace_root .. "/charters" then
				return workspace_root
			end
		end
		local parent = vim.fn.fnamemodify(dir, ":h")
		if parent == dir then
			break
		end
		dir = parent
	end

	return nil
end

--- Derive the project root (parent of .clearhead/) from a file inside a workspace.
--- Returns nil if the path isn't inside a recognized workspace charter tree.
local function project_root_for_path(path)
	local ws_root = workspace_root_for_charter_path(path)
	return ws_root and vim.fn.fnamemodify(ws_root, ":h") or nil
end

--- Derive a human-readable charter name from a file path inside charters/.
--- next.actions / README.md → parent directory name, except that root-charter
--- files at charters/next.actions or charters/README.md use the workspace /
--- project name instead of the literal directory name "charters".
local function charter_stem(path)
	local tail = vim.fn.fnamemodify(path, ":t")
	if
		tail == "next.actions"
		or tail == "next.completed.actions"
		or tail == "next.upcoming.actions"
		or tail == "README.md"
	then
		local parent = vim.fn.fnamemodify(path, ":h:t")
		if parent == "charters" then
			local workspace_root = workspace_root_for_charter_path(path)
			if workspace_root then
				return workspace_label(workspace_root)
			end
		end
		return parent
	end
	local stem = vim.fn.fnamemodify(path, ":t:r")
	stem = stem:gsub("%.completed$", ""):gsub("%.upcoming$", "")
	return stem
end

local function charter_workspace_root(path)
	if not (path and path ~= "" and path:match("%.md$")) then
		return nil
	end
	return workspace_root_for_charter_path(path)
end

local function find_charter_files(charters_root, predicate)
	if not is_directory(charters_root) then
		return {}
	end

	local files = vim.fs.find(function(name)
		if name:sub(1, 1) == "." then
			return false
		end
		return predicate(name)
	end, {
		path = charters_root,
		type = "file",
		limit = math.huge,
	})
	table.sort(files)
	return files
end

local function set_charter_mappings(bufnr)
	local function map(key, fn, desc)
		vim.keymap.set("n", key, fn, { buffer = bufnr, desc = desc })
	end

	map("<localleader>A", M.archive_charter, "Archive current charter")
	map("<localleader>C", M.close_charter, "Close current charter")
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

local function set_action_mappings(bufnr)
	local function map(key, fn, desc)
		vim.keymap.set("n", key, fn, { buffer = bufnr, desc = desc })
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
	map("<localleader>o", function()
		M.smart_new_action(0, vim.fn.line(".") - 1)
	end, "New action below")
	map(">>", function()
		M.indent_action(0, vim.fn.line(".") - 1)
	end, "Increase action depth")
	map("<<", function()
		M.dedent_action(0, vim.fn.line(".") - 1)
	end, "Decrease action depth")
	set_charter_mappings(bufnr)
end

-- ---------------------------------------------------------------------------
-- Setup / bootstrap
-- ---------------------------------------------------------------------------

M.setup = function(opts)
	config.load(opts)
	config_loaded = true
	M._plugin_init()
	return config.values
end

M._plugin_init = function()
	if bootstrap_done then
		return
	end

	local group = vim.api.nvim_create_augroup("clearhead", { clear = true })

	vim.api.nvim_create_autocmd("BufWritePre", {
		pattern = "*.actions",
		group = group,
		callback = function(args)
			if config.values.nvim_format_on_save then
				M.format(args.buf)
			end
		end,
	})

	vim.api.nvim_create_autocmd("BufWritePost", {
		pattern = "*.actions",
		group = group,
		callback = function(args)
			if config.values.nvim_archive_on_save then
				M.archive_saved(args.buf)
			end
		end,
	})

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

	-- Living-loop mappings in quickfix windows. The functions verify the list
	-- is a clearhead view before acting, so foreign quickfix lists just warn.
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "qf",
		group = group,
		callback = function(args)
			if not config.values.nvim_default_mappings then
				return
			end
			local function map(key, fn, desc)
				vim.keymap.set("n", key, fn, { buffer = args.buf, desc = desc })
			end
			map("<localleader>x", function()
				M.act_on_entry("complete")
			end, "Complete action under cursor")
			map("<localleader>_", function()
				M.act_on_entry("cancel")
			end, "Cancel action under cursor")
			map("<localleader>r", M.refresh_view, "Refresh clearhead view")
		end,
	})

	local function create_command(name, fn)
		if vim.fn.exists(":" .. name) == 0 then
			vim.api.nvim_create_user_command(name, fn, {})
		end
	end

	create_command("ClearheadInbox", function()
		M.open_inbox(0)
	end)
	create_command("ClearheadWorkspace", function()
		M.open_workspace(0)
	end)
	create_command("ClearheadProjectRoot", function()
		M.open_project_root(0)
	end)
	create_command("ClearheadDiff", function()
		vim.cmd("vertical diffsplit %")
	end)
	create_command("ClearheadArchiveWorkspace", function()
		M.archive_workspace()
	end)
	create_command("ClearheadPickActions", function()
		M.pick_action_file()
	end)
	create_command("ClearheadPickCharters", function()
		M.pick_charter_doc()
	end)
	if vim.fn.exists(":ClearheadQuery") == 0 then
		vim.api.nvim_create_user_command("ClearheadQuery", function(args)
			M.open_view(args.args ~= "" and args.args or nil)
		end, { nargs = "?" })
	end
	if vim.fn.exists(":ClearheadTree") == 0 then
		vim.api.nvim_create_user_command("ClearheadTree", function(args)
			M.open_tree(args.args ~= "" and args.args or nil)
		end, { nargs = "?" })
	end
	if vim.fn.exists(":ClearheadGraph") == 0 then
		vim.api.nvim_create_user_command("ClearheadGraph", function(args)
			M.open_graph(args.args ~= "" and args.args or nil)
		end, { nargs = "?" })
	end

	bootstrap_done = true
end

M._setup_actions_buffer = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if vim.b[bufnr].clearhead_actions_initialized then
		return
	end

	lsp.setup()
	vim.api.nvim_buf_call(bufnr, function()
		vim.opt_local.autoread = true
		vim.opt_local.conceallevel = 2
		vim.opt_local.concealcursor = "nc"

		local indent_width = tonumber(config.values.nvim_indent_width) or 4
		local indent_style = config.values.nvim_indent_style == "tabs" and "tabs" or "spaces"
		vim.opt_local.shiftwidth = indent_width
		vim.opt_local.tabstop = indent_width
		vim.opt_local.softtabstop = indent_width
		vim.opt_local.expandtab = (indent_style == "spaces")
	end)

	if config.values.nvim_default_mappings then
		set_action_mappings(bufnr)
	end

	vim.b[bufnr].clearhead_actions_initialized = true
end

M._setup_markdown_buffer = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if vim.b[bufnr].clearhead_markdown_initialized then
		return
	end
	if not config.values.nvim_default_mappings then
		return
	end

	local path = vim.api.nvim_buf_get_name(bufnr)
	if charter_workspace_root(path) then
		set_charter_mappings(bufnr)
		vim.b[bufnr].clearhead_markdown_initialized = true
	end
end

-- ---------------------------------------------------------------------------
-- File operations
-- ---------------------------------------------------------------------------

--- Archive terminal actions immediately after an active action file is saved.
--- This path is synchronous by design: allowing edits while the CLI moves
--- lines on disk could let a later write resurrect the archived actions.
M.archive_saved = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local filename = vim.api.nvim_buf_get_name(bufnr)
	local tail = vim.fn.fnamemodify(filename, ":t")
	if filename == "" or tail:match("%.completed%.actions$") or tail:match("%.upcoming%.actions$") then
		return
	end

	local bin = config.get_bin_path()
	if not bin then
		vim.notify("Cannot archive on save: clearhead CLI not found.", vim.log.levels.ERROR)
		return
	end
	local before = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	local result = vim.system(
		{ bin, "archive", "actions", "--file", filename },
		{ cwd = project_root_for_path(filename), text = true }
	):wait()
	if result.code ~= 0 then
		local detail = vim.trim(result.stderr or "")
		vim.notify(
			"Archive on save failed" .. (detail ~= "" and ": " .. detail or "."),
			vim.log.levels.ERROR
		)
		return
	end

	if vim.api.nvim_buf_is_valid(bufnr) and not vim.deep_equal(before, vim.fn.readfile(filename)) then
		vim.api.nvim_buf_call(bufnr, function()
			vim.cmd("silent edit!")
		end)
	end
end

M.archive = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local filename = vim.api.nvim_buf_get_name(bufnr)
	local bin = config.get_bin_path()
	if filename == "" or not bin then
		vim.notify("Cannot archive: buffer has no file or CLI not found.", vim.log.levels.ERROR)
		return
	end

	-- The CLI owns archival as one durable workspace mutation. Save the
	-- editor-owned buffer first; only reload or close it after the process
	-- reports success.
	vim.api.nvim_buf_call(bufnr, function()
		vim.cmd("write")
	end)

	-- .completed.actions files belong to closed-charter archival. Route them to
	-- `archive charter --file` so the CLI can infer root `next` charters too.
	local tail = vim.fn.fnamemodify(filename, ":t")
	if tail:match("%.completed%.actions$") then
		vim.fn.jobstart({ bin, "archive", "charter", "--file", filename }, {
			cwd = project_root_for_path(filename),
			on_exit = function(_, exit_code)
				vim.schedule(function()
					if exit_code == 0 then
						if vim.api.nvim_buf_is_valid(bufnr) then
							vim.api.nvim_buf_delete(bufnr, { force = true })
						end
						vim.notify("Current charter archived.")
					else
						vim.notify(
							"Current charter must have 'state: Closed' in its .md file. "
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

	vim.fn.jobstart({ bin, "archive", "actions", "--file", filename }, {
		cwd = project_root_for_path(filename),
		on_exit = function(_, exit_code)
			vim.schedule(function()
				if exit_code == 0 then
					if vim.api.nvim_buf_is_valid(bufnr) then
						vim.api.nvim_buf_call(bufnr, function()
							vim.api.nvim_command("edit!")
						end)
					end
					vim.notify("Archived completed actions.")
				else
					vim.notify("Archive failed.", vim.log.levels.ERROR)
				end
			end)
		end,
		on_stdout = on_output(nil),
		on_stderr = on_output("Archive error: "),
	})
end

--- Archive the current charter (requires state: Closed in its frontmatter).
--- Infers the charter from the currently open buffer's file path.
--- Pass force=true to sweep even if open actions remain.
--- Close the charter inferred from the current buffer (sets state to Closed,
--- creates the .md file if it doesn't exist yet).
M.close_charter = function(opts)
	opts = opts or {}
	local buf_path = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
	if buf_path == "" then
		vim.notify("No file in current buffer.", vim.log.levels.ERROR)
		return
	end
	local bin = config.get_bin_path()
	if not bin then
		vim.notify("clearhead binary not found.", vim.log.levels.ERROR)
		return
	end
	local cmd = { bin, "close", "charter", "--file", buf_path }
	if opts.dry_run then
		table.insert(cmd, "--dry-run")
	end
	run_charter_cmd(cmd, "Charter closed.", "Close charter", project_root_for_path(buf_path))
end

M.archive_charter = function(opts)
	opts = opts or {}
	local bufnr = vim.api.nvim_get_current_buf()
	local buf_path = vim.api.nvim_buf_get_name(bufnr)
	if buf_path == "" then
		vim.notify("No file in current buffer.", vim.log.levels.ERROR)
		return
	end

	local bin = config.get_bin_path()
	if not bin then
		vim.notify("clearhead binary not found.", vim.log.levels.ERROR)
		return
	end

	vim.api.nvim_buf_call(bufnr, function()
		vim.cmd("write")
	end)

	local cmd = { bin, "archive", "charter", "--file", buf_path }
	if opts.force then
		table.insert(cmd, "--force")
	end
	if opts.dry_run then
		table.insert(cmd, "--dry-run")
	end
	vim.fn.jobstart(cmd, {
		cwd = project_root_for_path(buf_path),
		on_exit = function(_, exit_code)
			vim.schedule(function()
				if exit_code == 0 then
					if not opts.dry_run and vim.api.nvim_buf_is_valid(bufnr) then
						vim.api.nvim_buf_delete(bufnr, { force = true })
					end
					vim.notify(opts.dry_run and "Charter archive dry run complete." or "Charter archived.")
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
		vim.lsp.buf.format({ name = "clearhead-lsp", bufnr = bufnr, async = false, timeout_ms = 5000 })
		return
	end

	-- LSP not attached to this buffer — can't do synchronous pre-write formatting.
	-- Fall through to normalize so the file is corrected on the post-write pass.
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
	local buf_path =
		vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(winnr == 0 and vim.api.nvim_get_current_win() or winnr))
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
		local files = find_charter_files(root.charters, function(name)
			return name:match("%.actions$")
				and not name:match("%.completed%.actions$")
				and not name:match("%.upcoming%.actions$")
		end)

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
		local files = find_charter_files(root.charters, function(name)
			return name:match("%.md$")
		end)

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
		config_loaded = true
		return { config = config.load(opts) }
	end,
	["plugin-init"] = function()
		M._plugin_init()
	end,
	["setup-actions-buffer"] = function(bufnr)
		M._setup_actions_buffer(bufnr)
	end,
	["setup-markdown-buffer"] = function(bufnr)
		M._setup_markdown_buffer(bufnr)
	end,
	["collect-workspace-roots"] = function(opts)
		return collect_workspace_roots(opts)
	end,
	["charter-workspace-root"] = function(path)
		return charter_workspace_root(path)
	end,
	["charter-stem"] = function(path)
		return charter_stem(path)
	end,
}

return M
