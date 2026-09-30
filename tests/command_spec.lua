local assert = require("luassert")
local command = require("clearhead.command")

describe("clearhead.command", function()
	local calls
	local tree

	before_each(function()
		calls = {}
		local function record(name)
			return {
				run = function(args)
					calls[#calls + 1] = { name, args }
				end,
			}
		end
		tree = {
			add = { action = record("add action") },
			query = {
				index = vim.tbl_extend("force", record("query index"), {
					complete = function(lead)
						return vim.tbl_filter(function(n)
							return vim.startswith(n, lead)
						end, { "agenda", "unscheduled" })
					end,
				}),
				tree = record("query tree"),
			},
		}
	end)

	describe("resolve", function()
		it("finds a leaf and passes the remaining words as args", function()
			local leaf, rest = command.resolve(tree, { "query", "index", "unscheduled" })
			assert.is_function(leaf.run)
			assert.are.same({ "unscheduled" }, rest)
		end)

		it("reports the valid choices when a branch is incomplete", function()
			local leaf, err = command.resolve(tree, { "query" })
			assert.is_nil(leaf)
			assert.are.equal("Clearhead: expected index|tree", err)
		end)

		it("names the unknown word with its path", function()
			local leaf, err = command.resolve(tree, { "query", "bogus" })
			assert.is_nil(leaf)
			assert.are.equal("Clearhead: unknown 'query bogus'", err)
		end)
	end)

	describe("complete", function()
		it("offers top-level verbs for an empty lead", function()
			assert.are.same({ "add", "query" }, command.complete(tree, "", "Clearhead "))
		end)

		it("filters by the word being typed", function()
			assert.are.same({ "query" }, command.complete(tree, "q", "Clearhead q"))
		end)

		it("offers nouns after a verb", function()
			assert.are.same({ "index", "tree" }, command.complete(tree, "", "Clearhead query "))
		end)

		it("delegates argument completion to the leaf", function()
			assert.are.same({ "unscheduled" }, command.complete(tree, "u", "Clearhead query index u"))
		end)

		it("returns nothing past an unknown word", function()
			assert.are.same({}, command.complete(tree, "", "Clearhead bogus "))
		end)
	end)

	describe("real tree", function()
		it("is fully resolvable: every leaf is reachable by its own path", function()
			local function walk(node, path)
				if type(node.run) == "function" then
					local leaf = command.resolve(command.tree, path)
					assert.are.equal(node, leaf)
					return
				end
				for name, child in pairs(node) do
					walk(child, vim.list_extend(vim.deepcopy(path), { name }))
				end
			end
			walk(command.tree, {})
		end)

		it("completes query view names from the CLI's list, minus targeted views", function()
			local names = require("clearhead.query")
			local saved = names.names
			names.names = function(family)
				assert.are.equal("index", family)
				return { "agenda", "chain", "unscheduled" }
			end
			local got = command.complete(command.tree, "", "Clearhead query index ")
			local none = command.complete(command.tree, "", "Clearhead query index agenda ")
			names.names = saved
			assert.are.same({ "agenda", "unscheduled" }, got)
			assert.are.same({}, none)
		end)

		it("mirrors the CLI verbs it shares", function()
			assert.is_not_nil(command.tree.add.action)
			assert.is_not_nil(command.tree.archive.charter)
			assert.is_not_nil(command.tree.query.index)
			assert.is_not_nil(command.tree.query.tree)
			assert.is_not_nil(command.tree.query.graph)
		end)
	end)
end)
