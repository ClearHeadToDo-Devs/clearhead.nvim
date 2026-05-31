local M = {}

local config = require("clearhead.config")

--- Populate the quickfix list with open actions that have source locations.
---
--- Calls `clearhead query named-run qflist` which returns JSON rows. Each row
--- carries ws_root (absolute) + source_file (relative to charter root) so
--- paths resolve correctly across multiple workspaces.
---
--- opts:
---   title (string?) — quickfix list title (default: "clearhead actions")
M.query_to_qflist = function(opts)
	opts = opts or {}
	local bin = config.get_bin_path()
	if not bin then
		vim.notify("clearhead binary not found.", vim.log.levels.ERROR)
		return
	end

	local chunks = {}
	vim.fn.jobstart({ bin, "query", "named-run", "qflist" }, {
		stdout_buffered = true,
		on_stdout = function(_, data)
			if data then
				vim.list_extend(chunks, data)
			end
		end,
		on_exit = function(_, exit_code)
			vim.schedule(function()
				if exit_code ~= 0 then
					vim.notify("clearhead qflist query failed (exit " .. exit_code .. ").", vim.log.levels.ERROR)
					return
				end

				local raw = table.concat(chunks, "\n")
				local ok, rows = pcall(vim.json.decode, raw)
				if not ok or type(rows) ~= "table" then
					vim.notify("clearhead: failed to parse qflist output.", vim.log.levels.ERROR)
					return
				end

				local items = {}
				for _, row in ipairs(rows) do
					local ws_root = row.ws_root
					local source_file = row.source_file
					if ws_root and source_file then
						items[#items + 1] = {
							filename = ws_root .. "/charters/" .. source_file,
							lnum = tonumber(row.source_line) or 1,
							col = 1,
							text = (row.name or "?") .. " [" .. (row.status or "?") .. "]",
						}
					end
				end

				if #items == 0 then
					vim.notify("clearhead: no actions with source locations found.", vim.log.levels.WARN)
					return
				end

				vim.fn.setqflist({}, " ", {
					title = opts.title or "clearhead actions",
					items = items,
				})
				vim.cmd("copen")
			end)
		end,
	})
end

return M
