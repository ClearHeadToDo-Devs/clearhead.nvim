local M = {}

local config = require("clearhead.config")
local query = require("clearhead.query")

--- Name of the query behind the current quickfix list, or nil if the list
--- is not a clearhead view.
local function current_view_name()
	local ctx = vim.fn.getqflist({ context = 1 }).context
	return type(ctx) == "table" and ctx.clearhead_query or nil
end

--- Map one index-contract row to a quickfix entry.
--- The line number navigates; the id acts: filename/lnum are the fragile
--- jump target, user_data carries the canonical id mutation verbs address.
M.to_qf_entry = function(row)
	local text = (row.name or "?") .. " [" .. (row.status or "?") .. "]"
	if row.due_date then
		text = text .. " due:" .. tostring(row.due_date):sub(1, 10)
	end
	return {
		filename = (row.charter_root or "") .. "/" .. (row.source_file or ""),
		lnum = tonumber(row.source_line) or 1,
		text = text,
		user_data = row.id,
	}
end

--- Run a named index query and render it as the quickfix list.
--- An empty result still renders (an empty agenda is an answer, not an
--- error). The list context records the query name so a refresh can
--- re-run the same query and rebuild in place.
M.open = function(name)
	name = name or "default"
	query.run_query(name, function(rows)
		vim.fn.setqflist({}, " ", {
			title = "clearhead: " .. name,
			context = { clearhead_query = name },
			items = vim.tbl_map(M.to_qf_entry, rows),
		})
		vim.cmd("copen")
	end)
end

--- Re-run the current clearhead view's query and rebuild the list in place —
--- the re-read half of the loop. The re-settle keeps the user's place: same
--- row index, clamped to the new list length.
M.refresh = function()
	local name = current_view_name()
	if not name then
		vim.notify("clearhead: current quickfix list is not a clearhead view.", vim.log.levels.WARN)
		return
	end
	local qf_win = vim.fn.getqflist({ winid = 1 }).winid
	local row = qf_win ~= 0 and vim.api.nvim_win_get_cursor(qf_win)[1] or 1
	query.run_query(name, function(rows)
		vim.fn.setqflist({}, "r", {
			title = "clearhead: " .. name,
			context = { clearhead_query = name },
			items = vim.tbl_map(M.to_qf_entry, rows),
		})
		if qf_win ~= 0 and #rows > 0 then
			vim.api.nvim_win_set_cursor(qf_win, { math.min(row, #rows), 0 })
		end
	end)
end

--- Fire a mutation verb ("complete" | "cancel") on the quickfix entry under
--- the cursor, then refresh — the write half of read → verb-by-id → re-read.
--- The entry's user_data carries the canonical id, so the CLI acts on exactly
--- that node. Save-gated: the CLI mutates the file on disk, so a modified
--- buffer for the entry's file aborts rather than diverge from it.
M.act = function(verb)
	local name = current_view_name()
	if not name then
		vim.notify("clearhead: current quickfix list is not a clearhead view.", vim.log.levels.WARN)
		return
	end
	local entry = vim.fn.getqflist()[vim.api.nvim_win_get_cursor(0)[1]]
	if not (entry and entry.user_data and entry.user_data ~= "") then
		vim.notify("clearhead: no addressable entry under cursor.", vim.log.levels.WARN)
		return
	end
	if entry.bufnr > 0 and vim.bo[entry.bufnr].modified then
		vim.notify("clearhead: save " .. vim.api.nvim_buf_get_name(entry.bufnr) .. " first.", vim.log.levels.WARN)
		return
	end
	local bin = config.get_bin_path()
	if not bin then
		vim.notify("clearhead binary not found.", vim.log.levels.ERROR)
		return
	end

	local chunks = {}
	vim.fn.jobstart({ bin, verb, "action", entry.user_data }, {
		-- Run from the entry's own directory so the CLI resolves the same
		-- workspace the entry came from.
		cwd = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(entry.bufnr), ":h"),
		stdout_buffered = true,
		on_stdout = function(_, data)
			if data then
				vim.list_extend(chunks, data)
			end
		end,
		on_exit = function()
			vim.schedule(function()
				-- Piped stdout means the CLI emitted a typed result (success
				-- or failure) — branch on kind rather than exit code.
				local ok, result = pcall(vim.json.decode, table.concat(chunks, "\n"))
				if not ok or type(result) ~= "table" then
					vim.notify("clearhead: " .. verb .. " produced no result.", vim.log.levels.ERROR)
					return
				end
				if result.kind == "not-found" then
					vim.notify("clearhead: entry is stale (action not found) — refreshing.", vim.log.levels.WARN)
				elseif result.kind == "already-closed" then
					vim.notify("clearhead: already " .. result.state .. ".")
				else
					vim.notify("clearhead: " .. result.kind .. ".")
				end
				-- The CLI wrote the file on disk; loaded buffers re-read it
				-- (actions buffers set autoread), then the list re-settles.
				vim.cmd("silent! checktime")
				M.refresh()
			end)
		end,
	})
end

return M
