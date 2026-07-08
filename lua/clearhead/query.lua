local M = {}

local config = require("clearhead.config")

--- Walk up from path to find the nearest ancestor containing .clearhead/.
local function find_project_root(start)
	local stat = vim.uv.fs_stat(start)
	local dir = (stat and stat.type == "directory") and start or vim.fn.fnamemodify(start, ":h")
	while dir and dir ~= "" do
		if vim.uv.fs_stat(dir .. "/.clearhead") then
			return dir
		end
		local parent = vim.fn.fnamemodify(dir, ":h")
		if parent == dir then
			break
		end
		dir = parent
	end
	return nil
end

--- Run a named index query and pass the parsed rows to callback(rows).
---
--- Calls `clearhead query index [name]`, which emits a JSON-LD document
--- (specifications/query_output.md). We are the "simple client": read the
--- @graph array, ignore the @context.
--- Each row satisfies the index contract: id (canonical urn:uuid IRI — the
--- address for mutation verbs), name, status, source_file, source_line,
--- charter_root, plus any sort keys the query emits (e.g. scheduled_at).
---
--- The caller decides what to do with the rows — qflist, vim.ui.select,
--- a telescope picker, or anything else.
---
--- name (string?) — named variant (e.g. "agenda"); omit for default
--- callback (function) — receives list of row tables, called on success
M.run_query = function(name, callback)
	local bin = config.get_bin_path()
	if not bin then
		vim.notify("clearhead binary not found.", vim.log.levels.ERROR)
		return
	end

	local buf_path = vim.api.nvim_buf_get_name(0)
	local start = buf_path ~= "" and buf_path or vim.fn.getcwd()
	local cwd = find_project_root(start) or config.expand_path(config.values.data_dir)

	local cmd = { bin, "query", "index" }
	if name then
		cmd[#cmd + 1] = name
	end

	local chunks = {}
	vim.fn.jobstart(cmd, {
		cwd = cwd,
		stdout_buffered = true,
		on_stdout = function(_, data)
			if data then
				vim.list_extend(chunks, data)
			end
		end,
		on_exit = function(_, exit_code)
			vim.schedule(function()
				if exit_code ~= 0 then
					vim.notify("clearhead query failed (exit " .. exit_code .. ").", vim.log.levels.ERROR)
					return
				end
				local raw = table.concat(chunks, "\n")
				local ok, rows = pcall(vim.json.decode, raw)
				if not ok or type(rows) ~= "table" then
					vim.notify("clearhead: failed to parse query output.", vim.log.levels.ERROR)
					return
				end
				callback(rows["@graph"] or rows)
			end)
		end,
	})
end

return M
