-- [nfnl] fnl/clearhead/init.fnl
local M = {}
local config = {auto_normalize = true, format_on_save = true, inbox_file = "~/.local/share/clearhead_cli/inbox.actions", lsp = {enable = true}, project_file = ".actions"}
local states = {["not-started"] = " ", ["in-progress"] = "-", blocked = "=", completed = "x", cancelled = "_"}
local state_cycle = {" ", "-", "=", "x", "_"}
local function expand_path(path)
  return vim.fn.expand(path)
end
local function get_current_state(line)
  return line:match("^%s*%[(.?)%]")
end
local function set_line_state(linenr, new_state)
  local line = vim.fn.getline(linenr)
  local new_line = line:gsub("^(%s*)%[.?%]", ("%1[" .. new_state .. "]"))
  return vim.fn.setline(linenr, new_line)
end
M["cycle-state"] = function()
  local linenr = vim.fn.line(".")
  local line = vim.fn.getline(linenr)
  local current = get_current_state(line)
  if current then
    local next_state = " "
    for i, state in ipairs(state_cycle) do
      if (state == current) then
        local next_idx
        if (i < #state_cycle) then
          next_idx = (i + 1)
        else
          next_idx = 1
        end
        next_state = state_cycle[next_idx]
        break
      else
      end
    end
    return set_line_state(linenr, next_state)
  else
    return nil
  end
end
M["set-state"] = function(state)
  local function _4_()
    local linenr = vim.fn.line(".")
    return set_line_state(linenr, state)
  end
  return _4_
end
M.normalize = function(bufnr)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  if (filename ~= "") then
    if (vim.fn.executable("clearhead_cli") == 1) then
      local function _5_(_, exit_code)
        if (exit_code == 0) then
          local function _6_()
            return vim.api.nvim_command("checktime")
          end
          return vim.schedule(_6_)
        else
          return nil
        end
      end
      local function _8_(_, data)
        if (data and (#data > 0)) then
          local msg = table.concat(data, "\n")
          if (msg ~= "") then
            return vim.notify(("clearhead_cli normalize error: " .. msg), vim.log.levels.ERROR)
          else
            return nil
          end
        else
          return nil
        end
      end
      return vim.fn.jobstart({"clearhead_cli", "normalize", filename, "--write"}, {on_exit = _5_, on_stderr = _8_})
    else
      return nil
    end
  else
    return nil
  end
end
M.format = function()
  local clients = vim.lsp.get_clients({name = "clearhead-lsp"})
  if (#clients > 0) then
    return vim.lsp.buf.format({name = "clearhead-lsp"})
  else
    return M.normalize(vim.api.nvim_get_current_buf())
  end
end
M["get-conform-opts"] = function()
  return {formatters = {clearhead_cli = {args = {"format", "$FILENAME"}, command = "clearhead_cli", stdin = false}}, formatters_by_ft = {actions = {"clearhead_cli"}}}
end
M["open-inbox"] = function()
  local inbox_path = expand_path(config.inbox_file)
  return vim.cmd(("edit " .. inbox_path))
end
M["open-dir"] = function()
  local cwd = vim.fn.getcwd()
  local actions_files = vim.fn.glob((cwd .. "/*.actions"), true, true)
  if (#actions_files > 0) then
    return vim.cmd(("edit " .. actions_files[1]))
  else
    return vim.notify("No .actions file found in current directory", vim.log.levels.WARN)
  end
end
M["setup-lsp"] = function(group)
  local bin_name = "clearhead_cli"
  local bin
  if (vim.fn.executable(bin_name) == 1) then
    bin = bin_name
  else
    local cargo_bin = (vim.fn.expand("~") .. "/.cargo/bin/clearhead_cli")
    if (vim.fn.executable(cargo_bin) == 1) then
      bin = cargo_bin
    else
      bin = nil
    end
  end
  if (config.lsp.enable and bin) then
    local function _14_(args)
      local root
      do
        local found = vim.fs.find({".git", "inbox.actions"}, {upward = true, path = args.file})
        if (#found > 0) then
          root = vim.fs.dirname(found[1])
        else
          root = vim.fn.getcwd()
        end
      end
      return vim.lsp.start({name = "clearhead-lsp", cmd = {bin, "lsp"}, root_dir = root})
    end
    return vim.api.nvim_create_autocmd("FileType", {pattern = "actions", group = group, callback = _14_})
  elseif (config.lsp.enable and not bin) then
    return vim.notify("clearhead_cli binary not found. LSP disabled. Install with 'cargo install --path .' in the CLI directory.", vim.log.levels.WARN)
  else
    return nil
  end
end
M.setup = function(opts)
  if opts then
    for k, v in pairs(opts) do
      config[k] = v
    end
  else
  end
  local group = vim.api.nvim_create_augroup("clearhead", {clear = true})
  M["setup-lsp"](group)
  if config.format_on_save then
    local function _15_()
      return M.format()
    end
    vim.api.nvim_create_autocmd("BufWritePre", {pattern = "*.actions", group = group, callback = _15_})
  else
  end
  local function _17_()
    vim.opt_local.conceallevel = 2
    vim.opt_local.concealcursor = "nc"
    return nil
  end
  vim.api.nvim_create_autocmd("FileType", {pattern = "actions", group = group, callback = _17_})
  vim.api.nvim_create_user_command("ClearheadInbox", M["open-inbox"], {})
  return vim.api.nvim_create_user_command("ClearheadOpenDir", M["open-dir"], {})
end
return M
