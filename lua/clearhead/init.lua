local config = require("clearhead.config")
local lsp = require("clearhead.lsp")
local actions = require("clearhead.actions")

local M = {}

M.cycle_state = actions.cycle_state
M.set_state = actions.set_state
M.smart_new_action = actions.smart_new_action
M.get_status = actions.get_status

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

M.setup = function(opts)
	config.load(opts)

	local group = vim.api.nvim_create_augroup("clearhead", { clear = true })

	if config.values.nvim_format_on_save then
		vim.api.nvim_create_autocmd("BufWritePre", {
			pattern = "*.actions",
			group = group,
			callback = function()
				M.format()
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
				map("<localleader><space>", M.cycle_state, "Cycle action state")
				map("<localleader>f", M.format, "Format action file")
				map("<localleader>i", M.open_inbox, "Open inbox")
				map("<localleader>p", M.open_workspace, "Browse workspace")
				map("<localleader>a", M.archive, "Archive completed actions")
				map("<localleader>o", M.smart_new_action, "New action below")
				map("<localleader>x", M.set_state("x"), "Set state to Completed")
				map("<localleader>-", M.set_state("-"), "Set state to In Progress")
				map("<localleader>=", M.set_state("="), "Set state to Blocked")
				map("<localleader>_", M.set_state("_"), "Set state to Cancelled")
				map("<localleader><bs>", M.set_state(" "), "Set state to Not Started")
			end
		end,
	})

	vim.api.nvim_create_user_command("ClearheadInbox", M.open_inbox, {})
	vim.api.nvim_create_user_command("ClearheadWorkspace", M.open_workspace, {})
	vim.api.nvim_create_user_command("ClearheadDiff", function()
		vim.cmd("vertical diffsplit %")
	end, {})
end

M.archive = function()
	local bufnr = vim.api.nvim_get_current_buf()
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

	vim.cmd("write")
	vim.fn.jobstart({ bin, "archive", "plans", "--file", filename }, {
		on_exit = function(_, exit_code)
			if exit_code == 0 then
				vim.schedule(function()
					vim.api.nvim_command("edit!")
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

M.format = function()
	local bufnr = vim.api.nvim_get_current_buf()
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
	local filename = vim.api.nvim_buf_get_name(bufnr)
	local bin = config.get_bin_path()
	if filename == "" or not bin then
		return
	end

	vim.fn.jobstart({ bin, "normalize", "file", filename, "--write" }, {
		on_exit = function(_, exit_code)
			if exit_code == 0 then
				vim.schedule(function()
					vim.api.nvim_command("checktime")
				end)
			end
		end,
		on_stderr = on_output("clearhead_cli normalize error: "),
	})
end

M.open_inbox = function()
	local inbox_path
	if config.values.nvim_inbox_file and config.values.nvim_inbox_file ~= "" then
		inbox_path = config.expand_path(config.values.nvim_inbox_file)
	else
		inbox_path = config.expand_path(config.values.data_dir) .. "/" .. config.values.default_file
	end
	vim.cmd("edit " .. inbox_path)
end

M.open_workspace = function()
	vim.cmd("edit " .. config.expand_path(config.values.data_dir))
end

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

M._testing = {
	["load-config-internal"] = function(opts)
		return { config = config.load(opts) }
	end,
}

return M
