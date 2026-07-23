local M = {}

local query = require("clearhead.query")
local states = {}

local function set_content(bufnr, dot)
	local lines = vim.split(dot, "\n", { plain = true })
	if lines[#lines] == "" then
		table.remove(lines)
	end
	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modifiable = false
end

local function configure_buffer(bufnr, name, dot)
	states[bufnr] = { name = name, dot = dot }
	vim.api.nvim_buf_set_name(bufnr, "clearhead://graph/" .. name .. ".dot")
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].filetype = "dot"
	set_content(bufnr, dot)

	local function map(key, fn, desc)
		vim.keymap.set("n", key, fn, { buffer = bufnr, nowait = true, silent = true, desc = desc })
	end
	map("r", function()
		M.refresh(bufnr)
	end, "Refresh dependency graph")
	map("p", function()
		M.preview(bufnr)
	end, "Preview dependency graph")
	map("q", "<cmd>close<cr>", "Close dependency graph")
end

M.refresh = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local state = states[bufnr]
	if not state then
		vim.notify("clearhead: current buffer is not a graph view.", vim.log.levels.WARN)
		return
	end
	query.run_graph(state.name, function(dot)
		if vim.api.nvim_buf_is_valid(bufnr) then
			state.dot = dot
			set_content(bufnr, dot)
		end
	end)
end

--- Render the current DOT buffer to SVG with Graphviz and open it using
--- Neovim's configured UI opener. DOT remains the durable editor buffer; the
--- SVG is a disposable visualization projection.
M.preview = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local state = states[bufnr]
	if not state then
		vim.notify("clearhead: current buffer is not a graph view.", vim.log.levels.WARN)
		return
	end
	if vim.fn.executable("dot") ~= 1 then
		vim.notify("clearhead: Graphviz `dot` executable not found.", vim.log.levels.ERROR)
		return
	end

	local svg = vim.fn.tempname() .. ".svg"
	local stderr = {}
	local job = vim.fn.jobstart({ "dot", "-Tsvg", "-o", svg }, {
		stdin = "pipe",
		stderr_buffered = true,
		on_stderr = function(_, data)
			if data then
				vim.list_extend(stderr, data)
			end
		end,
		on_exit = function(_, exit_code)
			vim.schedule(function()
				if exit_code ~= 0 then
					vim.notify("clearhead: DOT preview failed.\n" .. table.concat(stderr, "\n"), vim.log.levels.ERROR)
					return
				end
				if vim.ui.open then
					vim.ui.open(svg)
				else
					vim.fn.jobstart({ "xdg-open", svg }, { detach = true })
				end
			end)
		end,
	})
	if job <= 0 then
		vim.notify("clearhead: failed to start Graphviz `dot`.", vim.log.levels.ERROR)
		return
	end
	vim.fn.chansend(job, state.dot)
	vim.fn.chanclose(job, "stdin")
end

M.open = function(name)
	name = name or "dependencies"
	query.run_graph(name, function(dot)
		local buffer_name = "clearhead://graph/" .. name .. ".dot"
		local bufnr = vim.fn.bufnr(buffer_name)
		if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
			local winid = vim.fn.bufwinid(bufnr)
			if winid == -1 then
				vim.cmd("botright sbuffer " .. bufnr)
			else
				vim.api.nvim_set_current_win(winid)
			end
			if states[bufnr] then
				states[bufnr].dot = dot
				set_content(bufnr, dot)
			else
				configure_buffer(bufnr, name, dot)
			end
			return
		end
		vim.cmd("botright new")
		configure_buffer(vim.api.nvim_get_current_buf(), name, dot)
	end)
end

M._states = states

return M
