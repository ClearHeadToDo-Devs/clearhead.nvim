local describe = require('plenary.busted').describe
local it = require('plenary.busted').it
local assert = require('luassert')

describe("clearhead", function()
  local clearhead = require('clearhead')

  it("should load default configuration", function()
    local ctx = clearhead._testing["load-config-internal"]()
    assert.are.equal("inbox.actions", ctx.config.default_file)
    assert.are.same({}, ctx.config.additional_workspaces)
    assert.are.equal("spaces", ctx.config.nvim_indent_style)
    assert.are.equal(4, ctx.config.nvim_indent_width)
  end)

  it("should allow indentation defaults to be overridden", function()
    local ctx = clearhead._testing["load-config-internal"]({
      additional_workspaces = { "/tmp/extra" },
      nvim_indent_style = "tabs",
      nvim_indent_width = 2,
    })
    assert.are.same({ "/tmp/extra" }, ctx.config.additional_workspaces)
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

  it("should collect ancestor, sibling, and configured workspaces for pickers", function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")

    local global = tmp .. "/global"
    local platform = tmp .. "/platform"
    local plugin = platform .. "/clearhead.nvim"
    local sibling = platform .. "/clearhead-cli"

    vim.fn.mkdir(global .. "/charters", "p")
    vim.fn.mkdir(platform .. "/.clearhead/charters", "p")
    vim.fn.mkdir(plugin .. "/.clearhead/charters", "p")
    vim.fn.mkdir(sibling .. "/.clearhead/charters", "p")
    vim.fn.writefile({ "[ ] global" }, global .. "/charters/inbox.actions")
    vim.fn.writefile({ "[ ] root" }, platform .. "/.clearhead/charters/next.actions")
    vim.fn.writefile({ "[ ] plugin" }, plugin .. "/.clearhead/charters/next.actions")
    vim.fn.writefile({ "[ ] sibling" }, sibling .. "/.clearhead/charters/next.actions")

    clearhead._testing["load-config-internal"]({
      data_dir = global,
      additional_workspaces = { sibling .. "/.clearhead" },
    })

    local roots = clearhead._testing["collect-workspace-roots"]({
      current_file = plugin .. "/README.md",
      cwd = plugin,
    })

    local got = {}
    for _, root in ipairs(roots) do
      got[root.charters] = root.label
    end

    assert.are.equal("~", got[global .. "/charters"])
    assert.are.equal("platform", got[platform .. "/.clearhead/charters"])
    assert.are.equal("clearhead.nvim", got[plugin .. "/.clearhead/charters"])
    assert.are.equal("clearhead-cli", got[sibling .. "/.clearhead/charters"])
  end)

  it("should recognize charter markdown files", function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp .. "/.clearhead/charters/work", "p")
    local readme = tmp .. "/.clearhead/charters/work/README.md"
    vim.fn.writefile({ "---", "state: Active", "---" }, readme)

    local workspace = clearhead._testing["charter-workspace-root"](readme)
    assert.are.equal(tmp .. "/.clearhead", workspace)
  end)

  it("should register commands without requiring setup", function()
    clearhead._testing["plugin-init"]()
    assert.are.equal(2, vim.fn.exists(":ClearheadInbox"))
    assert.are.equal(2, vim.fn.exists(":ClearheadPickActions"))
  end)

  it("should apply actions buffer defaults from ftplugin hooks", function()
    clearhead._testing["load-config-internal"]({
      nvim_indent_style = "tabs",
      nvim_indent_width = 2,
    })

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    clearhead._testing["setup-actions-buffer"](bufnr)

    assert.are.equal(2, vim.bo[bufnr].shiftwidth)
    assert.are.equal(2, vim.bo[bufnr].tabstop)
    assert.are.equal(2, vim.bo[bufnr].softtabstop)
    assert.is_false(vim.bo[bufnr].expandtab)
  end)
end)
