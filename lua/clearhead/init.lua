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
				map("<localleader>o", function()
					M.smart_new_action(0, vim.fn.line(".") - 1)
				end, "New action below")
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

	vim.api.nvim_buf_call(bufnr, function()
		vim.cmd("write")
	end)
	vim.fn.jobstart({ bin, "archive", "plans", "--file", filename }, {
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
		on_stderr = on_output("clearhead_cli normalize error: "),
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
		path = config.expand_path(config.values.data_dir) .. "/" .. config.values.default_file
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
			open_file_in_win(winnr, candidate .. "/next.actions")
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

-- ---------------------------------------------------------------------------
-- conform.nvim integration helper
-- ---------------------------------------------------------------------------

M.get_conform_opts = function()
	return {
		formatters_by_ft = { actions = { "clearhead_cli" } },
		formatters = {
			clearhead_cli = {
				command = "clearhead_cli",
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
