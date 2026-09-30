local M = {}

local config = require("clearhead.config")

local function run_family(family, name, format, decode_json, callback)
	local clearhead = config.get_bin_path()
	if not clearhead then
		vim.notify("clearhead binary not found.", vim.log.levels.ERROR)
		return
	end

	-- `clearhead query` is the public read tool; it evaluates in-process over
	-- Core's canonical dataset. Run it from Neovim's cwd so its loader performs
	-- the same ancestor discovery a direct terminal invocation would. The buffer
	-- is deliberately not involved: :cd/:lcd and autochdir define the active
	-- query workspace.
	local cwd = vim.fn.getcwd()
	local cmd = { clearhead, "query", family }
	if name then
		cmd[#cmd + 1] = name
	end
	if format then
		vim.list_extend(cmd, { "--format", format })
	end

	local stdout = {}
	local stderr = {}
	vim.fn.jobstart(cmd, {
		cwd = cwd,
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			if data then
				vim.list_extend(stdout, data)
			end
		end,
		on_stderr = function(_, data)
			if data then
				vim.list_extend(stderr, data)
			end
		end,
		on_exit = function(_, exit_code)
			vim.schedule(function()
				if exit_code ~= 0 then
					local detail = table.concat(stderr, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
					local message = "clearhead " .. family .. " query failed (exit " .. exit_code .. ")."
					if detail ~= "" then
						message = message .. "\n" .. detail
					end
					vim.notify(message, vim.log.levels.ERROR)
					return
				end
				local raw = table.concat(stdout, "\n")
				if not decode_json then
					callback(raw)
					return
				end
				local ok, result = pcall(vim.json.decode, raw)
				if not ok or type(result) ~= "table" then
					vim.notify("clearhead: failed to parse " .. family .. " query output.", vim.log.levels.ERROR)
					return
				end
				callback(result)
			end)
		end,
	})
end

--- Parse the box-drawn table of `clearhead query list` into
--- `{ { name, type, source } }`. The CLI has no machine format for this yet,
--- so a layout change degrades to "no completions", never an error.
M.parse_list = function(text)
	local rows = {}
	for line in vim.gsplit(text or "", "\n", { plain = true }) do
		local cells = vim.split(line, "┆", { plain = true })
		if vim.startswith(line, "│") and #cells == 3 then
			local function cell(s)
				return vim.trim((s:gsub("│", "")))
			end
			local name = cell(cells[1])
			if name ~= "NAME" then
				rows[#rows + 1] = { name = name, type = cell(cells[2]), source = cell(cells[3]) }
			end
		end
	end
	return rows
end

--- Names of the available views of one family ("index" | "tree" | "graph"),
--- built-in and saved, straight from the CLI so completion cannot drift.
--- Synchronous: `query list` is a few milliseconds.
M.names = function(family)
	local bin = config.get_bin_path()
	if not bin then
		return {}
	end
	local done = vim.system({ bin, "query", "list" }, { cwd = vim.fn.getcwd(), text = true }):wait(2000)
	if done.code ~= 0 then
		return {}
	end
	local names = {}
	for _, row in ipairs(M.parse_list(done.stdout)) do
		if row.type == family then
			names[#names + 1] = row.name
		end
	end
	table.sort(names)
	return names
end

--- Run a named index query and pass its validated rows to callback(rows).
--- The index family's machine default is NDJSON; request JSON-LD explicitly
--- because this client consumes its semantic @graph framing.
M.run_query = function(name, callback)
	run_family("index", name, "jsonld", true, function(document)
		callback(document["@graph"] or document)
	end)
end

--- Run a named tree query and pass its validated nested nodes to callback(tree).
M.run_tree = function(name, callback)
	run_family("tree", name, "json", true, callback)
end

--- Run a named graph query and pass its Graphviz DOT projection to callback(dot).
M.run_graph = function(name, callback)
	run_family("graph", name, "dot", false, callback)
end

return M
