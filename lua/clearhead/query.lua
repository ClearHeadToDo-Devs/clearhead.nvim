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
