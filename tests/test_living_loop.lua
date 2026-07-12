-- End-to-end living loop: read → verb-by-id → re-read over a temp workspace.
-- Requires the `clearhead` binary on PATH; skips (exit 0) when absent so the
-- standalone suite stays runnable without a Rust toolchain.
-- Run: LUA_PATH="./lua/?.lua;./lua/?/init.lua;;" nvim -l tests/test_living_loop.lua
if vim.fn.executable("clearhead") == 0 then
	print("SKIP: clearhead binary not on PATH")
	return
end

local view = require("clearhead.view")

local function fail(msg)
	print("FAIL: " .. msg)
	os.exit(1)
end

local function wait_for(pred, what)
	if not vim.wait(8000, pred, 50) then
		fail("timeout waiting for " .. what)
	end
end

-- Build an initialized workspace in a temp dir and start nvim's cwd there so
-- the CLI's cwd-walk resolves it.
local root = vim.fn.tempname()
local charters = root .. "/.clearhead/charters"
vim.fn.mkdir(charters, "p")
local f = io.open(charters .. "/home.actions", "w")
f:write("[ ] first task #01951111-0000-7000-8000-000000000051\n")
f:write("[ ] second task #01951111-0000-7000-8000-000000000052\n")
f:write("[ ] third task #01951111-0000-7000-8000-000000000053\n")
f:close()
vim.cmd("cd " .. vim.fn.fnameescape(root))
if vim.fn.system({ "clearhead", "init" }) == nil or vim.v.shell_error ~= 0 then
	fail("clearhead init failed")
end

vim.notify = function() end -- keep headless output clean

view.open("default")
wait_for(function()
	return #vim.fn.getqflist() == 3
end, "initial list of 3")
print("PASS: view opens with 3 entries")

vim.cmd("copen")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
view.act("complete")
wait_for(function()
	return #vim.fn.getqflist() == 2
end, "list to re-settle to 2 entries")
print("PASS: verb-by-id completed the entry and the list re-settled")

local items = vim.fn.getqflist()
if items[1].text:find("second task", 1, true) or items[2].text:find("second task", 1, true) then
	fail("completed entry still in the list")
end
print("PASS: completed entry left the view")

if vim.api.nvim_win_get_cursor(0)[1] ~= 2 then
	fail("cursor did not keep its row through the re-settle")
end
print("PASS: re-settle kept the user's place")

local archive = io.open(charters .. "/home.completed.actions", "r")
if not archive then
	fail("completed archive missing")
end
local content = archive:read("*a")
archive:close()
if not content:find("second task", 1, true) then
	fail("second task not in completed archive")
end
print("PASS: action landed in the completed archive")

print("All living-loop tests passed!")
