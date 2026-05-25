local describe = require('plenary.busted').describe
local it = require('plenary.busted').it
local assert = require('luassert')

describe("clearhead", function()
  local clearhead = require('clearhead')

  it("should load default configuration", function()
    local ctx = clearhead._testing["load-config-internal"]()
    assert.are.equal("inbox.actions", ctx.config.default_file)
    assert.are.equal("spaces", ctx.config.nvim_indent_style)
    assert.are.equal(4, ctx.config.nvim_indent_width)
  end)

  it("should allow indentation defaults to be overridden", function()
    local ctx = clearhead._testing["load-config-internal"]({
      nvim_indent_style = "tabs",
      nvim_indent_width = 2,
    })
    assert.are.equal("tabs", ctx.config.nvim_indent_style)
    assert.are.equal(2, ctx.config.nvim_indent_width)
  end)

  it("should provide status string for a buffer", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "[x] Done",
      "[ ] Not Done",
    })
    vim.bo[bufnr].filetype = "actions"

    local status = clearhead.get_status(bufnr)
    assert.is_not_nil(status)
    -- Without a live treesitter parser in headless mode the parser may not be
    -- available; we just assert the function returns a string without error.
    assert.is_string(status)
  end)

  it("set_state should not touch other buffers", function()
    -- Create a decoy buffer to ensure set_state targets only the given bufnr.
    local decoy = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(decoy, 0, -1, false, { "[ ] Decoy action" })

    local target = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(target, 0, -1, false, { "[ ] Target action" })
    vim.bo[target].filetype = "actions"

    -- We can't assert treesitter state without the parser, but we can assert
    -- that calling set_state with an explicit bufnr does not modify the decoy.
    -- (A notifier warn is expected when parser is absent; that is acceptable.)
    clearhead.set_state(target, 0, "x")

    local decoy_lines = vim.api.nvim_buf_get_lines(decoy, 0, -1, false)
    assert.are.equal("[ ] Decoy action", decoy_lines[1])
  end)

  it("set_state_tree should not touch other buffers", function()
    local decoy = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(decoy, 0, -1, false, { "[ ] Decoy action" })

    local target = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(target, 0, -1, false, {
      "[ ] Parent",
      ">[ ] Child",
    })
    vim.bo[target].filetype = "actions"

    clearhead.set_state_tree(target, 0, "x")

    local decoy_lines = vim.api.nvim_buf_get_lines(decoy, 0, -1, false)
    assert.are.equal("[ ] Decoy action", decoy_lines[1])
  end)
end)
