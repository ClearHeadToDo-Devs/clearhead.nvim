-- Standalone test for the index-row → quickfix-entry mapping.
-- Run: LUA_PATH="./lua/?.lua;./lua/?/init.lua;;" nvim -l tests/test_view.lua
local view = require("clearhead.view")

local function assert_eq(actual, expected, name)
	if actual == expected then
		print("PASS: " .. name)
	else
		print("FAIL: " .. name .. " (Expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
		os.exit(1)
	end
end

-- A row emitted by `clearhead-graphd query index agenda` (index contract)
local entry = view.to_qf_entry({
	id = "urn:uuid:87a4395a-1dea-4d10-a82c-ae0b2e5d8985",
	name = "Make mutation verbs addressable by a bare id",
	status = "NotStarted",
	source_file = "agenda-view/next.actions",
	source_line = 3,
	charter_root = "/ws/.clearhead/charters",
	due_date = "2026-07-11T23:59:59Z",
})
assert_eq(entry.filename, "/ws/.clearhead/charters/agenda-view/next.actions", "locator composes charter_root + source_file")
assert_eq(entry.lnum, 3, "source_line becomes the jump line")
assert_eq(
	entry.text,
	"Make mutation verbs addressable by a bare id [NotStarted] due:2026-07-11",
	"display composes name, status, and due date"
)
assert_eq(entry.user_data, "urn:uuid:87a4395a-1dea-4d10-a82c-ae0b2e5d8985", "user_data carries the canonical id")

-- No due date → no due suffix; string line numbers still coerce
local undated = view.to_qf_entry({
	id = "urn:uuid:x",
	name = "Undated action",
	status = "InProgress",
	source_file = "next.actions",
	source_line = "7",
	charter_root = "/ws/charters",
})
assert_eq(undated.text, "Undated action [InProgress]", "no due suffix when due_date is absent")
assert_eq(undated.lnum, 7, "string source_line coerces to a number")

print("All view tests passed!")
