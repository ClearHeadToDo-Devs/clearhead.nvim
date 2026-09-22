local M = {}

local config = require("clearhead.config")

local current = nil

local function indent_columns(prefix, width)
	local columns = 0
	for char in prefix:gmatch(".") do
		columns = columns + (char == "\t" and width or 1)
	end
	return columns
end

---Turn an indented scratch outline into canonical action lines.
---Blank lines are ignored; optional Markdown bullets are stripped.
M.compile = function(lines, width)
	width = tonumber(width) or 4
	if width < 1 then
		return nil, "indent width must be positive"
	end

	local items = {}
	local base_indent
	for line_number, line in ipairs(lines) do
		if not line:match("^%s*$") then
			local prefix, text = line:match("^(%s*)(.-)%s*$")
			text = text:gsub("^[-*+]%s+", "")
			if text == "" then
				return nil, "line " .. line_number .. " has no action name"
			end
			local indent = indent_columns(prefix, width)
			base_indent = math.min(base_indent or indent, indent)
			items[#items + 1] = { indent = indent, line = line_number, text = text }
		end
	end

	if #items == 0 then
		return nil, "enter an action before saving"
	end

	local result = {}
	local previous_depth = 0
	for index, item in ipairs(items) do
		local relative = item.indent - base_indent
		if relative % width ~= 0 then
			return nil, "line " .. item.line .. " is not aligned to an indent width of " .. width
		end
		local depth = relative / width
		if depth > 5 then
			return nil, "line " .. item.line .. " exceeds the maximum action depth of 5"
		end
		if index == 1 and depth ~= 0 then
			return nil, "the first action must be at the root depth"
		end
		if depth > previous_depth + 1 then
			return nil, "line " .. item.line .. " skips an action depth"
		end

		local indent = string.rep(config.values.nvim_indent_style == "tabs" and "\t" or " ", depth)
		if config.values.nvim_indent_style ~= "tabs" then
			indent = string.rep(" ", depth * width)
		end
		result[#result + 1] = indent .. string.rep(">", depth) .. "[ ] " .. item.text
		previous_depth = depth
	end
	return result
end

local function inbox_path()
	if config.values.nvim_inbox_file and config.values.nvim_inbox_file ~= "" then
		return config.expand_path(config.values.nvim_inbox_file)
	end
	return config.expand_path(config.values.data_dir) .. "/charters/" .. config.values.default_file
end

---Append lines without overwriting an unsaved inbox buffer.
M.append = function(path, lines)
	local bufnr = vim.fn.bufnr(path)
	if bufnr > 0 and vim.api.nvim_buf_is_loaded(bufnr) then
		if vim.bo[bufnr].modified then
			return nil, "save the modified inbox before quick-adding"
		end
		vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
		local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function()
			vim.cmd("silent write")
		end)
		if not ok then
			return nil, err
		end
		return true
	end

	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	local ok, err = pcall(vim.fn.writefile, lines, path, "a")
	if not ok then
		return nil, err
	end
	return true
end

local function close_window()
	if current and vim.api.nvim_win_is_valid(current.win) then
		vim.api.nvim_win_close(current.win, true)
	end
	current = nil
end

local function submit(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local compiled, compile_error = M.compile(lines, config.values.nvim_indent_width)
	if not compiled then
		vim.notify("clearhead quick add: " .. compile_error, vim.log.levels.WARN)
		return
	end

	local path = inbox_path()
	local ok, append_error = M.append(path, compiled)
	if not ok then
		vim.notify("clearhead quick add: " .. append_error, vim.log.levels.ERROR)
		return
	end

	close_window()
	vim.notify("Added " .. #compiled .. " action" .. (#compiled == 1 and "" or "s") .. " to " .. path)
end

---Open a floating scratch outline. Indentation becomes action depth on submit.
M.open = function()
	if current and vim.api.nvim_win_is_valid(current.win) then
		vim.api.nvim_set_current_win(current.win)
		return
	end

	local width = math.min(72, math.max(1, vim.o.columns - 4))
	local height = math.min(12, math.max(1, vim.o.lines - 6))
	local bufnr = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(bufnr, true, {
		relative = "editor",
		row = math.floor((vim.o.lines - height) / 2 - 1),
		col = math.floor((vim.o.columns - width) / 2),
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " Quick Add ",
		title_pos = "center",
		footer = " indent subtasks · <C-s> save · q cancel ",
		footer_pos = "center",
	})
	current = { buf = bufnr, win = win }

	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].filetype = "clearhead-quick-add"
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].modifiable = true
	vim.bo[bufnr].expandtab = config.values.nvim_indent_style ~= "tabs"
	vim.bo[bufnr].shiftwidth = tonumber(config.values.nvim_indent_width) or 4
	vim.bo[bufnr].tabstop = tonumber(config.values.nvim_indent_width) or 4
	vim.bo[bufnr].softtabstop = tonumber(config.values.nvim_indent_width) or 4

	local map_opts = { buffer = bufnr, silent = true }
	vim.keymap.set({ "n", "i" }, "<C-s>", function()
		submit(bufnr)
	end, vim.tbl_extend("force", map_opts, { desc = "Save quick actions to inbox" }))
	vim.keymap.set("n", "q", close_window, vim.tbl_extend("force", map_opts, { desc = "Cancel quick add" }))
	vim.keymap.set("n", "<Esc>", close_window, map_opts)
	vim.cmd("startinsert")
end

return M
