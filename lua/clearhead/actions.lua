local M = {}

local STATE_QUERY = [[((state [
  (state_not_started)
  (state_completed)
  (state_in_progress)
  (state_blocked)
  (state_cancelled)
] @val))]]

local state_cycle = { " ", "-", "=", "x", "_" }

local function get_action_state_node(bufnr, linenr)
	local ok = pcall(vim.treesitter.get_parser, bufnr, "actions")
	if not ok then
		return nil
	end
	local root = vim.treesitter.get_parser(bufnr, "actions"):parse()[1]:root()
	local query = vim.treesitter.query.parse("actions", STATE_QUERY)
	local found = nil
	for _, node in query:iter_captures(root, bufnr, linenr, linenr + 1) do
		found = node
	end
	return found
end

local function maybe_add_completion_date(bufnr, linenr)
	local line = vim.fn.getline(linenr + 1)
	if not line:find("%%[0-9]") then
		vim.fn.setline(linenr + 1, line .. " %" .. vim.fn.strftime("%Y-%m-%dT%H:%M"))
	end
end

M.cycle_state = function()
	local bufnr = vim.api.nvim_get_current_buf()
	local linenr = vim.fn.line(".") - 1
	local node = get_action_state_node(bufnr, linenr)
	if not node then
		vim.notify("No action state found on this line", vim.log.levels.WARN)
		return
	end

	local current = vim.treesitter.get_node_text(node, bufnr)
	local next_state = state_cycle[1]
	for i, state in ipairs(state_cycle) do
		if state == current then
			next_state = state_cycle[(i % #state_cycle) + 1]
			break
		end
	end

	local srow, scol, erow, ecol = node:range()
	vim.api.nvim_buf_set_text(bufnr, srow, scol, erow, ecol, { next_state })

	if next_state == "x" then
		maybe_add_completion_date(bufnr, linenr)
	end
end

M.set_state = function(state)
	return function()
		local bufnr = vim.api.nvim_get_current_buf()
		local linenr = vim.fn.line(".") - 1
		local node = get_action_state_node(bufnr, linenr)
		if not node then
			vim.notify("No action state found on this line", vim.log.levels.WARN)
			return
		end

		local srow, scol, erow, ecol = node:range()
		vim.api.nvim_buf_set_text(bufnr, srow, scol, erow, ecol, { state })

		if state == "x" then
			maybe_add_completion_date(bufnr, linenr)
		end
	end
end

M.smart_new_action = function()
	local bufnr = vim.api.nvim_get_current_buf()
	local linenr = vim.fn.line(".") - 1
	local root = vim.treesitter.get_parser(bufnr, "actions"):parse()[1]:root()
	local node = root:named_descendant_for_range(linenr, 0, linenr, -1)

	local depth_markers = ""
	local current = node
	while current do
		local kind = current:type()
		if kind:find("depth(%d)_action") then
			depth_markers = string.rep(">", tonumber(kind:match("depth(%d)_action")))
			break
		end
		current = current:parent()
	end

	local line = vim.fn.getline(linenr + 1)
	local indent = line:match("^(%s*)")
	local prefix = indent .. depth_markers .. (depth_markers ~= "" and " " or "")

	vim.fn.append(linenr + 1, prefix .. "[ ]  ^" .. vim.fn.strftime("%Y-%m-%dT%H:%M"))
	vim.fn.cursor(linenr + 2, #(prefix .. "[ ] ") + 1)
	vim.cmd("startinsert!")
end

M.get_status = function()
	local bufnr = vim.api.nvim_get_current_buf()
	local ok = pcall(vim.treesitter.get_parser, bufnr, "actions")
	if not ok then
		return ""
	end

	local root = vim.treesitter.get_parser(bufnr, "actions"):parse()[1]:root()
	local query = vim.treesitter.query.parse("actions", STATE_QUERY)
	local total, completed = 0, 0

	for _, node in query:iter_captures(root, bufnr, 0, -1) do
		total = total + 1
		if vim.treesitter.get_node_text(node, bufnr) == "x" then
			completed = completed + 1
		end
	end

	return total > 0 and ("✓ " .. completed .. "/" .. total) or ""
end

return M
