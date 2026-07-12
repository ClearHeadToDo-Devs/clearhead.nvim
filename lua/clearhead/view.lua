local M = {}

local query = require("clearhead.query")

--- Map one index row (specifications/query_output.md) to a quickfix entry.
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

return M
