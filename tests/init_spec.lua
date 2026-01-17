local describe = require('plenary.busted').describe
local it = require('plenary.busted').it
local assert = require('luassert')

describe("clearhead", function()
  local clearhead = require('clearhead')

  it("should load default configuration", function()
    -- We can't easily call setup() in a headless test without a full environment,
    -- but we can test the internal loader we exported.
    local ctx = clearhead._testing.load-config-internal()
    assert.are.equal("inbox.actions", ctx.config.default_file)
  end)

  it("should provide status string", function()
    -- Mock a buffer with some actions
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      "[x] Done",
      "[ ] Not Done",
      "> [ ] Child"
    })
    vim.bo.filetype = "actions"
    
    -- Wait for treesitter to parse if possible, or just check the logic
    -- Note: Headless treesitter testing is advanced, but this is the right place for it.
    local status = clearhead.get_status()
    assert.is_not_nil(status)
  end)
end)
