local assert = require("luassert")

describe("clearhead", function()
  local clearhead = require('clearhead')

  it("should load default configuration", function()
    local ctx = clearhead._testing["load-config-internal"]()
    assert.are.equal("inbox.actions", ctx.config.default_file)
    assert.are.same({}, ctx.config.additional_workspaces)
    assert.are.equal("spaces", ctx.config.nvim_indent_style)
    assert.are.equal(4, ctx.config.nvim_indent_width)
    assert.are.equal("", ctx.config.nvim_graphd_binary_path)
    assert.is_false(ctx.config.nvim_archive_on_save)
    assert.are.equal("lcd", ctx.config.nvim_root_on_navigate)
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

  it("should use the workspace name for root next.actions charters", function()
    local tmp = vim.fn.tempname()
    local project = tmp .. "/sample-project"
    vim.fn.mkdir(project .. "/.clearhead/charters", "p")

    local root_actions = project .. "/.clearhead/charters/next.actions"
    local root_completed = project .. "/.clearhead/charters/next.completed.actions"
    local sub_readme = project .. "/.clearhead/charters/work/README.md"
    vim.fn.mkdir(project .. "/.clearhead/charters/work", "p")

    assert.are.equal("sample-project", clearhead._testing["charter-stem"](root_actions))
    assert.are.equal("sample-project", clearhead._testing["charter-stem"](root_completed))
    assert.are.equal("work", clearhead._testing["charter-stem"](sub_readme))
  end)

  it("resolves the workspace cwd for both project and user workspaces", function()
    local tmp = vim.fn.tempname()
    -- Project workspace: cwd is the project dir (the parent of .clearhead/).
    local project = tmp .. "/proj"
    vim.fn.mkdir(project .. "/.clearhead/charters", "p")
    vim.fn.writefile({ "[ ] root" }, project .. "/.clearhead/charters/next.actions")
    -- User / bare workspace: charters/ sits at the root with no .clearhead/
    -- marker, so cwd is the workspace dir itself — not its parent.
    local userws = tmp .. "/userws"
    vim.fn.mkdir(userws .. "/charters", "p")
    vim.fn.writefile({ "[ ] inbox" }, userws .. "/charters/inbox.actions")

    local resolve = clearhead._testing["workspace-cwd-for-path"]
    assert.are.equal(project, resolve(project .. "/.clearhead/charters/next.actions"))
    assert.are.equal(userws, resolve(userws .. "/charters/inbox.actions"))
    assert.is_nil(resolve(tmp .. "/loose.txt"))

    -- One resolver backs both the public API and the CLI-subprocess cwd, so the
    -- editor and the CLI can never disagree on where the workspace root is.
    assert.are.equal(userws, clearhead.workspace_root(userws .. "/charters/inbox.actions"))
  end)

  it("resolves an explicit standalone graphd binary", function()
    local config = require("clearhead.config")
    local old_executable = vim.fn.executable
    local old_values = vim.deepcopy(config.values)

    config.values.nvim_graphd_binary_path = "/opt/clearhead/bin/clearhead-graphd"
    vim.fn.executable = function(path)
      return path == "/opt/clearhead/bin/clearhead-graphd" and 1 or 0
    end

    local graphd = config.get_graphd_path()
    vim.fn.executable = old_executable
    config.values = old_values

    assert.are.equal("/opt/clearhead/bin/clearhead-graphd", graphd)
  end)

  it("configures the standalone clearhead-lsp command directly", function()
    local config = require("clearhead.config")
    local lsp = require("clearhead.lsp")
    local old_get_lsp_command = config.get_lsp_command
    local old_lsp_config = vim.lsp.config
    local old_lsp_enable = vim.lsp.enable
    local old_values = vim.deepcopy(config.values)
    local captured

    config.values.nvim_lsp_enable = true
    config.values.data_dir = "/tmp/clearhead-test"
    config.values.additional_workspaces = {}
    config.get_lsp_command = function()
      return { "/opt/clearhead/bin/clearhead-lsp" }, false
    end
    vim.lsp.config = function(name, opts)
      captured = { name = name, opts = opts }
    end
    vim.lsp.enable = function() end
    lsp.configured_signature = nil

    local ok, result = pcall(lsp.setup)
    config.get_lsp_command = old_get_lsp_command
    vim.lsp.config = old_lsp_config
    vim.lsp.enable = old_lsp_enable
    config.values = old_values

    assert.is_true(ok, result)
    assert.is_true(result)
    assert.are.equal("clearhead-lsp", captured.name)
    assert.are.same({ "/opt/clearhead/bin/clearhead-lsp" }, captured.opts.cmd)
  end)

  it("archives actions by saving, invoking the CLI, then reloading on success", function()
    local tmp = vim.fn.tempname()
    local project = tmp .. "/project"
    local path = project .. "/.clearhead/charters/next.actions"
    vim.fn.mkdir(project .. "/.clearhead/charters", "p")
    vim.fn.writefile({ "[ ] Task" }, path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "[x] Task" })

    local config = require("clearhead.config")
    local old_get_bin_path = config.get_bin_path
    local old_system = vim.system
    local captured
    config.get_bin_path = function()
      return "clearhead"
    end
    vim.system = function(cmd, opts)
      captured = { cmd = cmd, opts = opts, disk = vim.fn.readfile(path) }
      vim.fn.writefile({}, path)
      return { wait = function() return { code = 0, stdout = "", stderr = "" } end }
    end

    local ok, err = pcall(clearhead.archive, bufnr)
    config.get_bin_path = old_get_bin_path
    vim.system = old_system
    assert.is_true(ok, err)
    assert.are.same({ "[x] Task" }, captured.disk)
    assert.are.same({ "clearhead", "archive", "actions", "--file", path }, captured.cmd)
    assert.are.equal(project, captured.opts.cwd)
    assert.is_true(vim.api.nvim_buf_is_valid(bufnr))
    assert.is_false(vim.bo[bufnr].modified)
    assert.are.same({ "" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("archives terminal actions synchronously after save", function()
    local tmp = vim.fn.tempname()
    local project = tmp .. "/project"
    local path = project .. "/.clearhead/charters/next.actions"
    vim.fn.mkdir(project .. "/.clearhead/charters", "p")
    vim.fn.writefile({ "[ ] Keep", "[x] Archive" }, path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local bufnr = vim.api.nvim_get_current_buf()

    local config = require("clearhead.config")
    local old_get_bin_path = config.get_bin_path
    local old_system = vim.system
    local captured
    config.get_bin_path = function()
      return "clearhead"
    end
    vim.system = function(cmd, opts)
      captured = { cmd = cmd, opts = opts }
      vim.fn.writefile({ "[ ] Keep" }, path)
      return { wait = function() return { code = 0, stdout = "", stderr = "" } end }
    end

    local ok, err = pcall(clearhead.archive_saved, bufnr)
    config.get_bin_path = old_get_bin_path
    vim.system = old_system

    assert.is_true(ok, err)
    assert.are.same({ "clearhead", "archive", "actions", "--file", path }, captured.cmd)
    assert.are.equal(project, captured.opts.cwd)
    assert.are.same({ "[ ] Keep" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)

  it("does not turn completed-history saves into charter archival", function()
    local tmp = vim.fn.tempname()
    local path = tmp .. "/next.completed.actions"
    vim.fn.mkdir(tmp, "p")
    vim.fn.writefile({ "[x] History" }, path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))

    local old_system = vim.system
    local called = false
    vim.system = function()
      called = true
      error("must not run")
    end
    local ok, err = pcall(clearhead.archive_saved, vim.api.nvim_get_current_buf())
    vim.system = old_system

    assert.is_true(ok, err)
    assert.is_false(called)
  end)

  it("does not run manual and on-save archival twice", function()
    local tmp = vim.fn.tempname()
    local project = tmp .. "/project"
    local path = project .. "/.clearhead/charters/next.actions"
    vim.fn.mkdir(project .. "/.clearhead/charters", "p")
    vim.fn.writefile({ "[ ] Task" }, path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "[x] Task" })

    local config = require("clearhead.config")
    local old_get_bin_path = config.get_bin_path
    local old_system = vim.system
    local calls = 0
    config.get_bin_path = function() return "clearhead" end
    vim.system = function()
      calls = calls + 1
      vim.fn.writefile({}, path)
      return { wait = function() return { code = 0, stdout = "", stderr = "" } end }
    end
    clearhead._testing["load-config-internal"]({
      nvim_archive_on_save = true,
      nvim_format_on_save = false,
    })
    clearhead._testing["plugin-init"]()

    local ok, err = pcall(clearhead.archive, bufnr)
    config.get_bin_path = old_get_bin_path
    vim.system = old_system

    assert.is_true(ok, err)
    assert.are.equal(1, calls)
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
