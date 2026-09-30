--- Read-only scratch buffers holding a CLI command's text output, for CLI
--- verbs whose output is for reading, not acting on (`debug`, `query show`).
--- One buffer per command line: re-opening reuses it, `r` re-runs it, `q`
--- closes it.
local M = {}

local config = require("clearhead.config")

local function set_content(bufnr, text)
	local lines = vim.split(text, "\n", { plain = true })
	if lines[#lines] == "" then
		table.remove(lines)
	end
	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modifiable = false
end

--- Run `clearhead <args...>` from the current cwd (the active workspace, as
--- for queries) and pass its stdout to callback(text). Failures notify with
--- the CLI's stderr; the callback is not called.
local function run(args, callback)
	local bin = config.get_bin_path()
	if not bin then
		vim.notify("clearhead binary not found.", vim.log.levels.ERROR)
		return
	end
	local cmd = vim.list_extend({ bin }, args)
	vim.system(cmd, { cwd = vim.fn.getcwd(), text = true }, function(done)
		vim.schedule(function()
			if done.code ~= 0 then
				local message = ("clearhead %s failed (exit %d)."):format(table.concat(args, " "), done.code)
				vim.notify(message .. "\n" .. vim.trim(done.stderr or ""), vim.log.levels.ERROR)
				return
			end
			callback(done.stdout or "")
		end)
	end)
end

local function configure(bufnr, name, args, filetype)
	vim.api.nvim_buf_set_name(bufnr, name)
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].filetype = filetype or ""
	local function map(key, fn, desc)
		vim.keymap.set("n", key, fn, { buffer = bufnr, nowait = true, silent = true, desc = desc })
	end
	map("r", function()
		run(args, function(text)
			if vim.api.nvim_buf_is_valid(bufnr) then
				set_content(bufnr, text)
			end
		end)
	end, "Re-run " .. name)
	map("q", "<cmd>close<cr>", "Close " .. name)
end

--- Open the output of `clearhead <args...>` in a scratch split, reusing the
--- buffer if this command line is already open. `filetype` is optional.
M.open = function(args, filetype)
	local name = "clearhead://" .. table.concat(args, "/")
	run(args, function(text)
		local bufnr = vim.fn.bufnr(name)
		if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
			local winid = vim.fn.bufwinid(bufnr)
			if winid == -1 then
				vim.cmd("botright sbuffer " .. bufnr)
			else
				vim.api.nvim_set_current_win(winid)
			end
		else
			vim.cmd("botright new")
			bufnr = vim.api.nvim_get_current_buf()
			configure(bufnr, name, args, filetype)
		end
		set_content(bufnr, text)
	end)
end

return M
