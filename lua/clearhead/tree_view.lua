local M = {}

local query = require("clearhead.query")
local states = {}

local status_markers = {
	NotStarted = "○",
	InProgress = "◐",
	Blocked = "×",
	Completed = "●",
	Cancelled = "—",
}

local function display(node)
	local marker = node.kind == "charter" and "◆" or (status_markers[node.status] or "○")
	local text = marker .. " " .. (node.name or "?")
	if node.kind == "action" and node.priority then
		text = text .. "  !" .. tostring(node.priority)
	elseif node.status then
		text = text .. "  [" .. tostring(node.status) .. "]"
	end
	return text
end

--- Project the nested tree contract into display lines and their nodes.
M.render = function(tree, collapsed)
	collapsed = collapsed or {}
	local lines = {}
	local visible = {}

	local function visit(node, depth)
		local children = node.children or {}
		local has_children = #children > 0
		local branch = "  "
		if has_children then
			branch = collapsed[node.id] and "▸ " or "▾ "
		end
		lines[#lines + 1] = string.rep("  ", depth) .. branch .. display(node)
		visible[#visible + 1] = node
		if has_children and not collapsed[node.id] then
			for _, child in ipairs(children) do
				visit(child, depth + 1)
			end
		end
	end

	for _, root in ipairs(tree or {}) do
		visit(root, 0)
	end
	return lines, visible
end

local function render_buffer(bufnr)
	local state = states[bufnr]
	if not state or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	local lines, visible = M.render(state.tree, state.collapsed)
	state.visible = visible
	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modifiable = false
end

local function current_node(bufnr)
	local state = states[bufnr]
	local line = vim.api.nvim_win_get_cursor(0)[1]
	return state and state.visible and state.visible[line] or nil
end

local function source_path(node)
	if not (node and node.source_file and node.source_file ~= "") then
		return nil
	end
	if node.source_file:sub(1, 1) == "/" then
		return node.source_file
	end
	local root = (node.charter_root or ""):gsub("/$", "")
	return root ~= "" and (root .. "/" .. node.source_file) or node.source_file
end

M.toggle = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local state = states[bufnr]
	local node = current_node(bufnr)
	if not (state and node and node.children and #node.children > 0) then
		return
	end
	state.collapsed[node.id] = not state.collapsed[node.id]
	render_buffer(bufnr)
end

M.jump = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local node = current_node(bufnr)
	local path = source_path(node)
	if not path then
		vim.notify("clearhead: this tree node has no source file.", vim.log.levels.WARN)
		return
	end
	local line = tonumber(node.source_line) or 1
	vim.cmd("wincmd p")
	vim.cmd("edit +" .. line .. " " .. vim.fn.fnameescape(path))
end

M.refresh = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local state = states[bufnr]
	if not state then
		vim.notify("clearhead: current buffer is not a tree view.", vim.log.levels.WARN)
		return
	end
	query.run_tree(state.name, function(tree)
		if vim.api.nvim_buf_is_valid(bufnr) then
			state.tree = tree
			render_buffer(bufnr)
		end
	end)
end

local function configure_buffer(bufnr, name, tree)
	states[bufnr] = { name = name, tree = tree, collapsed = {} }
	vim.api.nvim_buf_set_name(bufnr, "clearhead://tree/" .. name)
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].filetype = "clearhead-tree"
	render_buffer(bufnr)

	local function map(key, fn, desc)
		vim.keymap.set("n", key, fn, { buffer = bufnr, nowait = true, silent = true, desc = desc })
	end
	map("<CR>", function()
		M.jump(bufnr)
	end, "Open source file")
	map("<Space>", function()
		M.toggle(bufnr)
	end, "Expand or collapse node")
	map("r", function()
		M.refresh(bufnr)
	end, "Refresh work tree")
	map("q", "<cmd>close<cr>", "Close work tree")
end

--- Run a tree-family query and render it in a read-only scratch split.
M.open = function(name)
	name = name or "work-map"
	query.run_tree(name, function(tree)
		local buffer_name = "clearhead://tree/" .. name
		local bufnr = vim.fn.bufnr(buffer_name)
		if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
			local winid = vim.fn.bufwinid(bufnr)
			if winid == -1 then
				vim.cmd("botright sbuffer " .. bufnr)
			else
				vim.api.nvim_set_current_win(winid)
			end
			if states[bufnr] then
				states[bufnr].tree = tree
				render_buffer(bufnr)
			else
				configure_buffer(bufnr, name, tree)
			end
			return
		end
		vim.cmd("botright new")
		configure_buffer(vim.api.nvim_get_current_buf(), name, tree)
	end)
end

M._states = states

return M
