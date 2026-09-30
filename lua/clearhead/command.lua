--- The `:Clearhead` command: one verb-noun tree that drives both dispatch and
--- completion. A node with `run` is a leaf; anything else is a table of
--- subcommands. Where a verb exists in the CLI it uses the CLI's words.
local M = {}

local function ch()
	return require("clearhead")
end

local function first(args)
	return args[1]
end

-- Index views that return nothing without a target. The CLI runs them through
-- their own verb (`query chain <query>`, mirrored below), so they stay out of
-- `query index` completion.
local needs_target = { chain = true }

local function starting_with(lead, candidates)
	return vim.tbl_filter(function(c)
		return vim.startswith(c, lead)
	end, candidates)
end

local function view_names(family)
	return vim.tbl_filter(function(name)
		return not needs_target[name]
	end, require("clearhead.query").names(family))
end

--- A `query <family> [name]` leaf: runs `open(name)` and completes `name`
--- from the CLI's own view list.
local function view(family, open)
	return {
		run = function(args)
			open(first(args))
		end,
		complete = function(lead, rest)
			return #rest > 0 and {} or starting_with(lead, view_names(family))
		end,
	}
end

--- `query index [name] [--charter <charter>]`: the words after `index` go to
--- the CLI unchanged, so the CLI validates them; completion offers view names,
--- then the flag, then charter aliases.
local index = {
	run = function(args)
		ch().open_view(vim.list_extend({ "index" }, args))
	end,
	complete = function(lead, rest)
		if rest[#rest] == "--charter" then
			return starting_with(lead, require("clearhead.query").charters())
		end
		local flags = vim.tbl_contains(rest, "--charter") and {} or { "--charter" }
		local names = #rest == 0 and view_names("index") or {}
		return starting_with(lead, vim.list_extend(names, flags))
	end,
}

--- `query chain [target]`: walk an action's predecessor chain. The target
--- defaults to the action under the cursor (a quickfix entry or an actions
--- buffer line); the CLI resolves ids, aliases and names alike.
local chain = {
	run = function(args)
		local target = first(args) or ch().action_id_under_cursor()
		if not target then
			vim.notify("Clearhead: query chain needs a target or an action under the cursor", vim.log.levels.ERROR)
			return
		end
		ch().open_view({ "chain", target })
	end,
}

M.tree = {
	add = {
		action = {
			run = function()
				ch().open_quick_add()
			end,
		},
	},
	open = {
		root = {
			run = function()
				ch().open_inbox(0)
			end,
		},
		project = {
			run = function()
				ch().open_project_root(0)
			end,
		},
		workspace = {
			run = function()
				ch().open_workspace(0)
			end,
		},
	},
	pick = {
		actions = {
			run = function()
				ch().pick_action_file()
			end,
		},
		charters = {
			run = function()
				ch().pick_charter_doc()
			end,
		},
	},
	archive = {
		charter = {
			run = function()
				ch().archive_workspace()
			end,
		},
	},
	debug = {
		run = function()
			ch().open_cli_output({ "debug" })
		end,
	},
	query = {
		index = index,
		chain = chain,
		tree = view("tree", function(name)
			ch().open_tree(name)
		end),
		graph = view("graph", function(name)
			ch().open_graph(name)
		end),
	},
}

local function is_leaf(node)
	return type(node.run) == "function"
end

local function names(node, prefix)
	local out = {}
	for name in pairs(node) do
		if vim.startswith(name, prefix) then
			out[#out + 1] = name
		end
	end
	table.sort(out)
	return out
end

--- Walk `fargs` down `tree`. Returns `leaf, rest` on success, or
--- `nil, message` when a word is missing or unknown.
function M.resolve(tree, fargs)
	local node, path = tree, {}
	for i, word in ipairs(fargs) do
		if is_leaf(node) then
			return node, vim.list_slice(fargs, i)
		end
		if not node[word] then
			return nil, ("Clearhead: unknown '%s'"):format(table.concat(path, " ") .. " " .. word)
		end
		node = node[word]
		path[#path + 1] = word
	end
	if is_leaf(node) then
		return node, {}
	end
	local usage = table.concat(names(node, ""), "|")
	return nil, ("Clearhead: expected %s"):format(usage)
end

--- Candidates for the word under the cursor. `cmdline` is the whole command
--- line; the words before `arglead` pick the node to complete from.
function M.complete(tree, arglead, cmdline)
	local words = vim.split(cmdline, "%s+", { trimempty = true })
	table.remove(words, 1) -- ":Clearhead" itself
	if arglead ~= "" then
		table.remove(words) -- the word being typed
	end

	local node = tree
	for i, word in ipairs(words) do
		if is_leaf(node) then
			return node.complete and node.complete(arglead, vim.list_slice(words, i)) or {}
		end
		node = node[word]
		if not node then
			return {}
		end
	end
	if is_leaf(node) then
		return node.complete and node.complete(arglead, {}) or {}
	end
	return names(node, arglead)
end

--- Entry point for the user command.
function M.run(fargs)
	local leaf, rest = M.resolve(M.tree, fargs)
	if not leaf then
		vim.notify(rest, vim.log.levels.ERROR)
		return
	end
	leaf.run(rest)
end

function M.register()
	if vim.fn.exists(":Clearhead") ~= 0 then
		return
	end
	vim.api.nvim_create_user_command("Clearhead", function(args)
		M.run(args.fargs)
	end, {
		nargs = "*",
		complete = function(arglead, cmdline)
			return M.complete(M.tree, arglead, cmdline)
		end,
	})
end

return M
