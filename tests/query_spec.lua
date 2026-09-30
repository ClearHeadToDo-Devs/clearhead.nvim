local assert = require("luassert")
local query = require("clearhead.query")

-- Verbatim shape of `clearhead query list` (box-drawn table).
local LIST = table.concat({
	"┌─────────────────────┬───────┬──────────┐",
	"│ NAME                ┆ TYPE  ┆ SOURCE   │",
	"╞═════════════════════╪═══════╪══════════╡",
	"│ open-actions        ┆ —     ┆ built-in │",
	"├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌┤",
	"│ agenda              ┆ index ┆ built-in │",
	"├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌┤",
	"│ my-filter           ┆ index ┆ project  │",
	"├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌┤",
	"│ work-map            ┆ tree  ┆ built-in │",
	"└─────────────────────┴───────┴──────────┘",
}, "\n")

describe("clearhead.query", function()
	describe("parse_list", function()
		it("reads name, type and source, skipping borders and the header", function()
			assert.are.same({
				{ name = "open-actions", type = "—", source = "built-in" },
				{ name = "agenda", type = "index", source = "built-in" },
				{ name = "my-filter", type = "index", source = "project" },
				{ name = "work-map", type = "tree", source = "built-in" },
			}, query.parse_list(LIST))
		end)

		it("degrades to no rows on unrecognised output", function()
			assert.are.same({}, query.parse_list("error: something else"))
			assert.are.same({}, query.parse_list(nil))
		end)
	end)
end)
