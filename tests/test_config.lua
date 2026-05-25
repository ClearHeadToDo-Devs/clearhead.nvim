-- Simple test script for configuration
local clearhead = require('clearhead')
local testing = clearhead._testing

-- Mocking vim functions if necessary
if not vim.tbl_extend then
    vim.tbl_extend = function(behavior, deep, ...)
        -- Very basic implementation for testing if real vim is not available
        local res = {}
        local tables = {...}
        for _, t in ipairs(tables) do
            for k, v in pairs(t) do
                res[k] = v
            end
        end
        return res
    end
end

local function assert_eq(actual, expected, name)
    if actual == expected then
        print("PASS: " .. name)
    else
        print("FAIL: " .. name .. " (Expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
        os.exit(1)
    end
end

-- Test default config loading
local ctx = testing["load-config-internal"]()
assert_eq(ctx.config.default_file, "inbox.actions", "Default file should be inbox.actions")
assert_eq(#ctx.config.additional_workspaces, 0, "Default additional_workspaces should be empty")
assert_eq(ctx.config.nvim_indent_style, "spaces", "Default indent style should be spaces")
assert_eq(ctx.config.nvim_indent_width, 4, "Default indent width should be 4")

-- Test user options override
local ctx2 = testing["load-config-internal"]({
    default_file = "test.actions",
    additional_workspaces = {"/tmp/extra"},
    nvim_indent_style = "tabs",
    nvim_indent_width = 2,
})
assert_eq(ctx2.config.default_file, "test.actions", "User option should override default_file")
assert_eq(ctx2.config.additional_workspaces[1], "/tmp/extra", "User option should override additional_workspaces")
assert_eq(ctx2.config.nvim_indent_style, "tabs", "User option should override indent style")
assert_eq(ctx2.config.nvim_indent_width, 2, "User option should override indent width")

print("All config tests passed!")
