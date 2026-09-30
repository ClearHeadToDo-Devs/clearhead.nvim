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

		describe("query index", function()
			local query = require("clearhead.query")
			local saved_names, saved_charters

			before_each(function()
				saved_names, saved_charters = query.names, query.charters
				query.names = function(family)
					assert.are.equal("index", family)
					return { "agenda", "chain", "unscheduled" }
				end
				query.charters = function()
					return { "clearhead.nvim", "nvim-subcommands" }
				end
			end)

			after_each(function()
				query.names, query.charters = saved_names, saved_charters
			end)

			local function complete(line)
				local lead = line:match("(%S*)$")
				return command.complete(command.tree, lead, "Clearhead query index " .. line)
			end

			it("completes view names minus targeted views, then the flag", function()
				assert.are.same({ "agenda", "unscheduled", "--charter" }, complete(""))
				assert.are.same({ "--charter" }, complete("agenda "))
			end)

			it("completes charter aliases after --charter, and offers the flag once", function()
				assert.are.same({ "nvim-subcommands" }, complete("agenda --charter nv"))
				assert.are.same({}, complete("agenda --charter nvim-subcommands "))
			end)

			it("passes every word after index to the CLI", function()
				local ch = require("clearhead")
				local saved = ch.open_view
				local got
				ch.open_view = function(args)
					got = args
				end
				command.run({ "query", "index", "agenda", "--charter", "nvim-subcommands" })
				ch.open_view = saved
				assert.are.same({ "index", "agenda", "--charter", "nvim-subcommands" }, got)
			end)
		end)

		describe("query chain", function()
			local ch = require("clearhead")
			local saved_open, saved_id, opened, notified

			before_each(function()
				saved_open, saved_id = ch.open_view, ch.action_id_under_cursor
				opened, notified = nil, nil
				ch.open_view = function(args)
					opened = args
				end
				ch.action_id_under_cursor = function()
					return "urn:uuid:under-cursor"
				end
				stub(vim, "notify", function(msg)
					notified = msg
				end)
			end)

			after_each(function()
				ch.open_view, ch.action_id_under_cursor = saved_open, saved_id
				vim.notify:revert()
			end)

			it("walks an explicit target", function()
				command.run({ "query", "chain", "view-args" })
				assert.are.same({ "chain", "view-args" }, opened)
			end)

			it("defaults to the action under the cursor", function()
				command.run({ "query", "chain" })
				assert.are.same({ "chain", "urn:uuid:under-cursor" }, opened)
			end)

			it("errors without a target or an action under the cursor", function()
				ch.action_id_under_cursor = function()
					return nil
				end
				command.run({ "query", "chain" })
				assert.is_nil(opened)
				assert.is_truthy(notified:find("needs a target", 1, true))
			end)
		end)

		it("mirrors the CLI verbs it shares", function()
			assert.is_not_nil(command.tree.add.action)
			assert.is_not_nil(command.tree.archive.charter)
			assert.is_not_nil(command.tree.query.index)
			assert.is_not_nil(command.tree.query.tree)
			assert.is_not_nil(command.tree.query.graph)
			assert.is_not_nil(command.tree.debug)
		end)
	end)
end)
