local M = {}

local config = require("clearhead.config")

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

	-- Workspace resolution is delegated to the CLI (specifications/
	-- configuration.md, Workspace Resolution): run it from Neovim's cwd and
	-- the binary walks up for .clearhead/ itself. This respects :cd/:lcd and
	-- autochdir, matching how the CLI resolves a workspace from a terminal —
	-- the buffer's directory is not involved.
	local cwd = vim.fn.getcwd()

	local cmd = { bin, "query", "index" }
	if name then
		cmd[#cmd + 1] = name
	end
	-- The index family's machine default is NDJSON. Request the semantic
	-- document explicitly because this client consumes its @graph framing.
	vim.list_extend(cmd, { "--format", "jsonld" })

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
