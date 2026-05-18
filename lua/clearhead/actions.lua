local M = {}

local STATE_QUERY = [[((state [
  (state_not_started)
  (state_completed)
  (state_in_progress)
  (state_blocked)
  (state_cancelled)
] @val))]]

local state_cycle = { " ", "-", "=", "x", "_" }

--- Returns the state value node (e.g. state_completed) on the given 0-indexed line,
--- or nil if none found.
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

--- Appends a completion timestamp to the given 0-indexed line if one is not already present.
local function maybe_add_completion_date(bufnr, linenr)
	local line = vim.api.nvim_buf_get_lines(bufnr, linenr, linenr + 1, false)[1] or ""
	if not line:find("%%[0-9]") then
		vim.api.nvim_buf_set_lines(bufnr, linenr, linenr + 1, false, {
			line .. " %" .. vim.fn.strftime("%Y-%m-%dT%H:%M"),
		})
	end
end

--- Returns the enclosing root_action or depth{N}_action node for the given
--- 0-indexed line, or nil if the cursor is not inside an action.
local function get_enclosing_action_node(bufnr, linenr)
	local ok = pcall(vim.treesitter.get_parser, bufnr, "actions")
	if not ok then
		return nil
	end
	local root = vim.treesitter.get_parser(bufnr, "actions"):parse()[1]:root()
	local node = root:named_descendant_for_range(linenr, 0, linenr, -1)
	local current = node
	while current do
		local kind = current:type()
		if kind == "root_action" or kind:match("^depth%d_action$") then
			return current
		end
		current = current:parent()
	end
	return nil
end

--- Cycle the action state on the given 0-indexed line.
--- bufnr: buffer number (0 = current)
--- linenr: 0-indexed line number
M.cycle_state = function(bufnr, linenr)
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

--- Set the action state on the given 0-indexed line.
--- bufnr: buffer number (0 = current)
--- linenr: 0-indexed line number
--- state: one of " ", "-", "=", "x", "_"
M.set_state = function(bufnr, linenr, state)
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

--- Set the action state on the given line AND all of its children.
--- bufnr: buffer number (0 = current)
--- linenr: 0-indexed line number of the parent action
--- state: one of " ", "-", "=", "x", "_"
M.set_state_tree = function(bufnr, linenr, state)
	local action_node = get_enclosing_action_node(bufnr, linenr)
	if not action_node then
		vim.notify("No action found on this line", vim.log.levels.WARN)
		return
	end

	local ok = pcall(vim.treesitter.get_parser, bufnr, "actions")
	if not ok then
		return
	end
	local root = vim.treesitter.get_parser(bufnr, "actions"):parse()[1]:root()

	-- The action node's range spans the entire subtree (parent + all children).
	local srow, _, erow, _ = action_node:range()

	local query = vim.treesitter.query.parse("actions", STATE_QUERY)
	local changes = {}
	for _, node in query:iter_captures(root, bufnr, srow, erow + 1) do
		local ns, nc, _, nec = node:range()
		table.insert(changes, { row = ns, scol = nc, ecol = nec })
	end

	-- All state values are single characters — no position shifts between edits.
	for _, c in ipairs(changes) do
		vim.api.nvim_buf_set_text(bufnr, c.row, c.scol, c.row, c.ecol, { state })
		if state == "x" then
			maybe_add_completion_date(bufnr, c.row)
		end
	end
end

--- Insert a new action below the given 0-indexed line, at the same depth.
--- bufnr: buffer number (0 = current)
--- linenr: 0-indexed line number
M.smart_new_action = function(bufnr, linenr)
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

	local line = vim.api.nvim_buf_get_lines(bufnr, linenr, linenr + 1, false)[1] or ""
	local indent = line:match("^(%s*)")
	local prefix = indent .. depth_markers .. (depth_markers ~= "" and " " or "")

	vim.api.nvim_buf_set_lines(bufnr, linenr + 1, linenr + 1, false, {
		prefix .. "[ ]  ^" .. vim.fn.strftime("%Y-%m-%dT%H:%M"),
	})
	vim.fn.cursor(linenr + 2, #(prefix .. "[ ] ") + 1)
	vim.cmd("startinsert!")
end

--- Increase the depth of the action on the given 0-indexed line by one.
--- Prepends a '>' marker immediately before the state bracket.
--- bufnr: buffer number (0 = current)
--- linenr: 0-indexed line number
M.indent_action = function(bufnr, linenr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local line = vim.api.nvim_buf_get_lines(bufnr, linenr, linenr + 1, false)[1]
	if not line then
		return
	end
	-- Capture: leading whitespace | zero or more '>' markers | rest (includes state bracket)
	local ws, markers, rest = line:match("^(%s*)(>*)(.*)$")
	if not rest then
		return
	end
	vim.api.nvim_buf_set_lines(bufnr, linenr, linenr + 1, false, { ws .. markers .. ">" .. rest })
end

--- Decrease the depth of the action on the given 0-indexed line by one.
--- Removes one '>' marker. Notifies and does nothing on root-level actions.
--- bufnr: buffer number (0 = current)
--- linenr: 0-indexed line number
M.dedent_action = function(bufnr, linenr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local line = vim.api.nvim_buf_get_lines(bufnr, linenr, linenr + 1, false)[1]
	if not line then
		return
	end
	local ws, markers, rest = line:match("^(%s*)(>*)(.*)$")
	if not rest then
		return
	end
	if markers == "" then
		vim.notify("Already at root depth.", vim.log.levels.WARN)
		return
	end
	vim.api.nvim_buf_set_lines(bufnr, linenr, linenr + 1, false, { ws .. markers:sub(1, -2) .. rest })
end

--- Return a summary string like "✓ 2/5" for the given buffer, or "" if no actions.
--- bufnr: buffer number (0 = current)
M.get_status = function(bufnr)
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
