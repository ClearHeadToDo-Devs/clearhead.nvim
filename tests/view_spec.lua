local assert = require("luassert")
local view = require("clearhead.view")

describe("quickfix view projection", function()
	it("maps graph index rows to source-addressable quickfix entries", function()
		local entry = view.to_qf_entry({
			id = "urn:uuid:87a4395a-1dea-4d10-a82c-ae0b2e5d8985",
			name = "Make mutation verbs addressable by a bare id",
			status = "NotStarted",
			source_file = "agenda-view/next.actions",
			source_line = 3,
			charter_root = "/ws/.clearhead/charters",
			due_date = "2026-07-11T23:59:59Z",
		})

		assert.are.equal("/ws/.clearhead/charters/agenda-view/next.actions", entry.filename)
		assert.are.equal(3, entry.lnum)
		assert.are.equal(
			"Make mutation verbs addressable by a bare id [NotStarted] due:2026-07-11",
			entry.text
		)
		assert.are.equal("urn:uuid:87a4395a-1dea-4d10-a82c-ae0b2e5d8985", entry.user_data)
	end)

	it("handles undated rows and coerces string line numbers", function()
		local entry = view.to_qf_entry({
			id = "urn:uuid:x",
			name = "Undated action",
			status = "InProgress",
			source_file = "next.actions",
			source_line = "7",
			charter_root = "/ws/charters",
		})

		assert.are.equal("Undated action [InProgress]", entry.text)
		assert.are.equal(7, entry.lnum)
	end)
end)
