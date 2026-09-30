local assert = require("luassert")
local config = require("clearhead.config")
local query = require("clearhead.query")

-- A stand-in `clearhead`: answers each command line with the JSON the real CLI
-- emits when piped, so these specs cover the run-and-decode path end to end.
local FAKE_CLI = [[#!/bin/sh
case "$*" in
"query list") cat <<'JSON'
[
  { "name": "open-actions", "type": null, "source": "built-in" },
  { "name": "unscheduled", "type": "index", "source": "built-in" },
  { "name": "agenda", "type": "index", "source": "built-in" },
  { "name": "work-map", "type": "tree", "source": "project" }
]
JSON
;;
"debug") echo '{ "workspace": { "workspace_name": "proofws", "resolution": "xdg-default", "root_charter": null } }' ;;
"read charters --format json") echo '{ "charters": [ { "alias": "work" }, { "title": "No alias" }, { "alias": "home" } ] }' ;;
esac
]]

-- What a CLI that predates piped JSON prints for `query list`.
local OLD_CLI = [[#!/bin/sh
echo "┌──────┬───────┬──────────┐"
echo "│ NAME ┆ TYPE  ┆ SOURCE   │"
]]

describe("clearhead.query CLI lookups", function()
	local original_bin
	local script

	local function use(cli)
		script = vim.fn.tempname()
		vim.fn.writefile(vim.split(cli, "\n", { plain = true }), script)
		vim.fn.setfperm(script, "rwx------")
		config.get_bin_path = function()
			return script
		end
	end

	before_each(function()
		original_bin = config.get_bin_path
		use(FAKE_CLI)
	end)

	after_each(function()
		config.get_bin_path = original_bin
		vim.fn.delete(script)
	end)

	it("lists one family's view names, sorted", function()
		assert.are.same({ "agenda", "unscheduled" }, query.names("index"))
		assert.are.same({ "work-map" }, query.names("tree"))
		assert.are.same({}, query.names("graph"))
	end)

	it("reports the workspace the CLI resolved, with nulls as nil", function()
		local workspace = query.workspace()
		assert.are.equal("proofws", workspace.workspace_name)
		assert.are.equal("xdg-default", workspace.resolution)
		assert.is_nil(workspace.root_charter)
	end)

	it("completes charter aliases, skipping charters without one", function()
		assert.are.same({ "home", "work" }, query.charters())
	end)

	it("degrades to nothing when the CLI does not emit JSON or is missing", function()
		use(OLD_CLI)
		assert.are.same({}, query.names("index"))
		assert.is_nil(query.workspace())
		assert.are.same({}, query.charters())

		config.get_bin_path = function()
			return nil
		end
		assert.are.same({}, query.names("index"))
		assert.is_nil(query.workspace())
	end)
end)
