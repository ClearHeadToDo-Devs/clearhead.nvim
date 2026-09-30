local M = {}

local config = require("clearhead.config")

--- Run `clearhead query <args...> --format <format>`. `args` is the argv
--- after `query` (e.g. `{ "index", "agenda", "--charter", "x" }`); the
--- client owns only `--format`.
local function run(args, format, decode_json, callback)
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
	local cmd = vim.list_extend({ clearhead, "query" }, args)
	vim.list_extend(cmd, { "--format", format })

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
					local message = "clearhead query " .. args[1] .. " failed (exit " .. exit_code .. ")."
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
					vim.notify("clearhead: failed to parse query " .. args[1] .. " output.", vim.log.levels.ERROR)
					return
				end
				callback(result)
			end)
		end,
	})
end

--- Run `clearhead <args...>` synchronously from the cwd and decode its piped
--- JSON (nulls become nil). Returns nil when the binary is missing, the
--- command fails, or the output is not JSON — e.g. a CLI that predates piped
--- JSON for this command — so callers degrade instead of erroring. Only for
--- commands that take a few milliseconds.
local function cli_json(args)
	local bin = config.get_bin_path()
	if not bin then
		return nil
	end
	local done = vim.system(vim.list_extend({ bin }, args), { cwd = vim.fn.getcwd(), text = true }):wait(2000)
	if done.code ~= 0 then
		return nil
	end
	local ok, doc = pcall(vim.json.decode, done.stdout or "", { luanil = { object = true, array = true } })
	return ok and type(doc) == "table" and doc or nil
end

--- Names of the available views of one family ("index" | "tree" | "graph"),
--- built-in and saved, straight from `clearhead query list` so completion
--- cannot drift.
M.names = function(family)
	local names = {}
	for _, row in ipairs(cli_json({ "query", "list" }) or {}) do
		if row.type == family then
			names[#names + 1] = row.name
		end
	end
	table.sort(names)
	return names
end

--- The workspace the CLI resolves from the cwd, per `clearhead debug`
--- (`workspace_name`, `resolution`, `resolved_data_root`, ...), or nil.
M.workspace = function()
	return (cli_json({ "debug" }) or {}).workspace
end

--- Normalize an index view spec to the argv after `clearhead query`: a list
--- passes through, a name (or nil, the CLI's "default") becomes
--- `{ "index", name }`.
M.index_args = function(spec)
	if type(spec) == "table" then
		return spec
	end
	return { "index", spec }
end

--- Aliases of the charters the CLI can see from the cwd, for `--charter`
--- completion. Charters without an alias are skipped: titles carry spaces,
--- which a command-line word cannot.
M.charters = function()
	local doc = cli_json({ "read", "charters", "--format", "json" }) or {}
	local aliases = {}
	for _, charter in ipairs(doc.charters or {}) do
		if type(charter.alias) == "string" then
			aliases[#aliases + 1] = charter.alias
		end
	end
	table.sort(aliases)
	return aliases
end

--- Run an index-shaped query and pass its validated rows to callback(rows).
--- `spec` is a view name or the argv after `clearhead query` (see index_args),
--- so views with arguments (`--charter`, `chain <target>`) go through here too.
--- The index family's machine default is NDJSON; request JSON-LD explicitly
--- because this client consumes its semantic @graph framing.
M.run_query = function(spec, callback)
	run(M.index_args(spec), "jsonld", true, function(document)
		callback(document["@graph"] or document)
	end)
end

--- Run a named tree query and pass its validated nested nodes to callback(tree).
M.run_tree = function(name, callback)
	run({ "tree", name }, "json", true, callback)
end

--- Run a named graph query and pass its Graphviz DOT projection to callback(dot).
M.run_graph = function(name, callback)
	run({ "graph", name }, "dot", false, callback)
end

return M
