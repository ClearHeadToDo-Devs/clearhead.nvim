local M = {}
local config = {data_dir = "", config_dir = "", default_file = "inbox.actions", project_files = {"next.actions"}, use_project_config = true, nvim_auto_normalize = true, nvim_format_on_save = true, nvim_lsp_enable = true, nvim_inbox_file = "", nvim_lsp_binary_path = "", nvim_default_mappings = true}
local function expand_path(path)
  if (path and (path ~= "")) then
    return vim.fn.expand(path)
  else
    return path
  end
end
local function get_default_config_dir()
  local xdg_config = os.getenv("XDG_CONFIG_HOME")
  local base
  if (xdg_config and (xdg_config ~= "")) then
    base = xdg_config
  else
    base = (vim.fn.expand("~") .. "/.config")
  end
  return (base .. "/clearhead")
end
local function get_default_data_dir()
  local xdg_data = os.getenv("XDG_DATA_HOME")
  local base
  if (xdg_data and (xdg_data ~= "")) then
    base = xdg_data
  else
    base = (vim.fn.expand("~") .. "/.local/share")
  end
  return (base .. "/clearhead")
end
local function load_env()
  local env_config = {}
  local mappings = {CLEARHEAD_DATA_DIR = "data_dir", CLEARHEAD_CONFIG_DIR = "config_dir", CLEARHEAD_DEFAULT_FILE = "default_file", CLEARHEAD_PROJECT_FILES = "project_files", CLEARHEAD_USE_PROJECT_CONFIG = "use_project_config", CLEARHEAD_NVIM_AUTO_NORMALIZE = "nvim_auto_normalize", CLEARHEAD_NVIM_FORMAT_ON_SAVE = "nvim_format_on_save", CLEARHEAD_NVIM_LSP_ENABLE = "nvim_lsp_enable", CLEARHEAD_NVIM_INBOX_FILE = "nvim_inbox_file", CLEARHEAD_NVIM_LSP_BINARY_PATH = "nvim_lsp_binary_path", CLEARHEAD_NVIM_DEFAULT_MAPPINGS = "nvim_default_mappings"}
  for env_var, key in pairs(mappings) do
    local val = os.getenv(env_var)
    if (val and (val ~= "")) then
      local parsed_val
      if ((val == "true") or (val == "false")) then
        parsed_val = (val == "true")
      else
        local num = tonumber(val)
        if num then
          parsed_val = num
        else
          if (val:find("^%[") and val:find("%]$")) then
            parsed_val = vim.fn.json_decode(val)
          else
            parsed_val = val
          end
        end
      end
      env_config[key] = parsed_val
    else
    end
  end
  return env_config
end
local function discover_project(project_files)
  local current = vim.fn.getcwd()
  local found = nil
  local depth = 0
  while (not found and (depth < 100)) do
    do
      local dot_clearhead = (current .. "/.clearhead")
      if (vim.fn.isdirectory(dot_clearhead) == 1) then
        local _8_
        do
          local cfg = (dot_clearhead .. "/config.json")
          if (vim.fn.filereadable(cfg) == 1) then
            _8_ = cfg
          else
            _8_ = nil
          end
        end
        found = {root = current, config = _8_, ["default-file"] = (dot_clearhead .. "/inbox.actions")}
      else
        for _, f in ipairs(project_files) do
          local f_path = (current .. "/" .. f)
          if (not found and (vim.fn.filereadable(f_path) == 1)) then
            local _10_
            do
              local cfg = (current .. "/.clearhead/config.json")
              if (vim.fn.filereadable(cfg) == 1) then
                _10_ = cfg
              else
                _10_ = nil
              end
            end
            found = {root = current, config = _10_, ["default-file"] = f_path}
          else
          end
        end
      end
    end
    if found then
    else
      local parent = vim.fn.fnamemodify(current, ":h")
      if (parent == current) then
        depth = 100
      else
        current = parent
        depth = (depth + 1)
      end
    end
  end
  return found
end
local function read_json_file(path)
  if (path and (vim.fn.filereadable(path) == 1)) then
    local lines = vim.fn.readfile(path)
    local content = table.concat(lines, "")
    if (content and (content ~= "")) then
      return vim.fn.json_decode(content)
    else
      return {}
    end
  else
    return {}
  end
end
local function load_config_internal(user_opts)
  local defaults = {data_dir = "", config_dir = "", default_file = "inbox.actions", project_files = {"next.actions"}, use_project_config = true, nvim_auto_normalize = true, nvim_format_on_save = true, nvim_lsp_enable = true, nvim_inbox_file = "", nvim_lsp_binary_path = "", nvim_default_mappings = true}
  local global_config_dir = get_default_config_dir()
  local global_config_path = (global_config_dir .. "/config.json")
  local global_config = read_json_file(global_config_path)
  local base_config = vim.tbl_extend("force", defaults, global_config)
  local project_context
  if base_config.use_project_config then
    project_context = discover_project(base_config.project_files)
  else
    project_context = nil
  end
  local base_config0
  if (project_context and project_context.config) then
    base_config0 = vim.tbl_extend("force", base_config, read_json_file(project_context.config))
  else
    base_config0 = base_config
  end
  local base_config1 = vim.tbl_extend("force", base_config0, load_env())
  local final_config
  if user_opts then
    final_config = vim.tbl_extend("force", base_config1, user_opts)
  else
    final_config = base_config1
  end
  if ((final_config.config_dir == "") or not final_config.config_dir) then
    final_config.config_dir = global_config_dir
  else
    final_config.config_dir = expand_path(final_config.config_dir)
  end
  if ((final_config.data_dir == "") or not final_config.data_dir) then
    final_config.data_dir = get_default_data_dir()
  else
    final_config.data_dir = expand_path(final_config.data_dir)
  end
  return {config = final_config, project = project_context}
end
M._testing = {["load-config-internal"] = load_config_internal, ["discover-project"] = discover_project}
local states = {["not-started"] = " ", ["in-progress"] = "-", blocked = "=", completed = "x", cancelled = "_"}
local state_cycle = {" ", "-", "=", "x", "_"}
local function get_action_state_node(bufnr, linenr)
  local ok = pcall(vim.treesitter.get_parser, bufnr, "actions")
  if ok then
    local parser = vim.treesitter.get_parser(bufnr, "actions")
    local tree = parser:parse()[1]
    local root = tree:root()
    local query = vim.treesitter.query.parse("actions", "((state [\n                         (state_not_started)\n                         (state_completed)\n                         (state_in_progress)\n                         (state_blocked)\n                         (state_cancelled)\n                        ] @val))")
    local found_node = nil
    for id, node in query:iter_captures(root, bufnr, linenr, (linenr + 1)) do
      found_node = node
    end
    return found_node
  else
    return nil
  end
end
M["cycle-state"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local linenr = (vim.fn.line(".") - 1)
  local node = get_action_state_node(bufnr, linenr)
  if node then
    local current = vim.treesitter.get_node_text(node, bufnr)
    local ns = " "
    for i, state in ipairs(state_cycle) do
      if (state == current) then
        local next_idx
        if (i < #state_cycle) then
          next_idx = (i + 1)
        else
          next_idx = 1
        end
        ns = state_cycle[next_idx]
        break
      else
      end
    end
    do
      local srow, scol, erow, ecol = node:range()
      vim.api.nvim_buf_set_text(bufnr, srow, scol, erow, ecol, {ns})
    end
    if (ns == "x") then
      local line = vim.fn.getline((linenr + 1))
      if not line:find("%%[0-9]") then
        local now = vim.fn.strftime("%Y-%m-%dT%H:%M")
        local new_line = (line .. " %" .. now)
        return vim.fn.setline((linenr + 1), new_line)
      else
        return nil
      end
    else
      return nil
    end
  else
    return vim.notify("No action state found on this line", vim.log.levels.WARN)
  end
end
M["set-state"] = function(state)
  local function _29_()
    local bufnr = vim.api.nvim_get_current_buf()
    local linenr = (vim.fn.line(".") - 1)
    local node = get_action_state_node(bufnr, linenr)
    if node then
      do
        local srow, scol, erow, ecol = node:range()
        vim.api.nvim_buf_set_text(bufnr, srow, scol, erow, ecol, {state})
      end
      if (state == "x") then
        local line = vim.fn.getline((linenr + 1))
        if not line:find("%%[0-9]") then
          local now = vim.fn.strftime("%Y-%m-%dT%H:%M")
          local new_line = (line .. " %" .. now)
          return vim.fn.setline((linenr + 1), new_line)
        else
          return nil
        end
      else
        return nil
      end
    else
      return vim.notify("No action state found on this line", vim.log.levels.WARN)
    end
  end
  return _29_
end
M["get-status"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local ok = pcall(vim.treesitter.get_parser, bufnr, "actions")
  if ok then
    local parser = vim.treesitter.get_parser(bufnr, "actions")
    local tree = parser:parse()[1]
    local root = tree:root()
    local query = vim.treesitter.query.parse("actions", "((state [\n                         (state_not_started)\n                         (state_completed)\n                         (state_in_progress)\n                         (state_blocked)\n                         (state_cancelled)\n                        ] @val))")
    local total = 0
    local completed = 0
    for id, node in query:iter_captures(root, bufnr, 0, -1) do
      total = (total + 1)
      if (vim.treesitter.get_node_text(node, bufnr) == "x") then
        completed = (completed + 1)
      else
      end
    end
    if (total > 0) then
      return ("\226\156\147 " .. completed .. "/" .. total)
    else
      return ""
    end
  else
    return ""
  end
end
M["smart-new-action"] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local linenr = (vim.fn.line(".") - 1)
  local parser = vim.treesitter.get_parser(bufnr, "actions")
  local tree = parser:parse()[1]
  local root = tree:root()
  local node = root:named_descendant_for_range(linenr, 0, linenr, -1)
  local depth_markers = ""
  local current = node
  while current do
    local type = current:type()
    if type:find("depth(%d)_action") then
      local depth = type:match("depth(%d)_action")
      local markers = string.rep(">", tonumber(depth))
      depth_markers = markers
      current = nil
    else
      current = current:parent()
    end
  end
  local line = vim.fn.getline((linenr + 1))
  local indent = line:match("^(%s*)")
  local now = vim.fn.strftime("%Y-%m-%dT%H:%M")
  local prefix
  local _37_
  if (#depth_markers > 0) then
    _37_ = " "
  else
    _37_ = ""
  end
  prefix = (indent .. depth_markers .. _37_)
  vim.fn.append((linenr + 1), (prefix .. "[ ]  ^" .. now))
  vim.fn.cursor((linenr + 2), (#(prefix .. "[ ] ") + 1))
  return vim.cmd("startinsert!")
end
local function get_bin_path()
  local bin_name = "clearhead_cli"
  if (config.nvim_lsp_binary_path and (config.nvim_lsp_binary_path ~= "")) then
    local expanded = expand_path(config.nvim_lsp_binary_path)
    if (vim.fn.executable(expanded) == 1) then
      return expanded
    else
      return nil
    end
  else
    if (vim.fn.executable(bin_name) == 1) then
      return bin_name
    else
      local cargo_bin = (vim.fn.expand("~") .. "/.cargo/bin/clearhead_cli")
      if (vim.fn.executable(cargo_bin) == 1) then
        return cargo_bin
      else
        return nil
      end
    end
  end
end
M.archive = function()
  local filename = vim.api.nvim_buf_get_name(0)
  local bin = get_bin_path()
  if ((filename ~= "") and bin) then
    vim.cmd("write")
    local function _43_(_, exit_code)
      if (exit_code == 0) then
        local function _44_()
          vim.api.nvim_command("edit!")
          return vim.notify("Archived completed actions.")
        end
        return vim.schedule(_44_)
      else
        return vim.notify("Archive failed.", vim.log.levels.ERROR)
      end
    end
    local function _46_(_, data)
      if (data and (#data > 0)) then
        local msg = table.concat(data, "\n")
        if ((msg ~= "") and not msg:find("^%s*$")) then
          return vim.notify(msg)
        else
          return nil
        end
      else
        return nil
      end
    end
    local function _49_(_, data)
      if (data and (#data > 0)) then
        local msg = table.concat(data, "\n")
        if ((msg ~= "") and not msg:find("^%s*$")) then
          return vim.notify(("Archive error: " .. msg), vim.log.levels.ERROR)
        else
          return nil
        end
      else
        return nil
      end
    end
    return vim.fn.jobstart({bin, "archive", filename}, {on_exit = _43_, on_stdout = _46_, on_stderr = _49_})
  else
    return vim.notify("Cannot archive: buffer has no file or CLI not found.", vim.log.levels.ERROR)
  end
end
M.normalize = function(bufnr)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local bin = get_bin_path()
  if ((filename ~= "") and bin) then
    local function _53_(_, exit_code)
      if (exit_code == 0) then
        local function _54_()
          return vim.api.nvim_command("checktime")
        end
        return vim.schedule(_54_)
      else
        return nil
      end
    end
    local function _56_(_, data)
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
    vim.fn.jobstart({bin, "normalize", filename, "--write"}, {on_exit = _53_, on_stderr = _56_})
    return nil
  else
    return nil
  end
end
M.format = function()
  local clients = vim.lsp.get_clients({name = "clearhead-lsp"})
  if (#clients > 0) then
    return vim.lsp.buf.format({name = "clearhead-lsp"})
  else
    if config.nvim_auto_normalize then
      return M.normalize(vim.api.nvim_get_current_buf())
    else
      return nil
    end
  end
end
M["get-conform-opts"] = function()
  return {formatters_by_ft = {actions = {"clearhead_cli"}}, formatters = {clearhead_cli = {command = "clearhead_cli", args = {"format", "$FILENAME"}, stdin = false}}}
end
M["open-inbox"] = function()
  local ctx = load_config_internal()
  local cfg = ctx.config
  local project = ctx.project
  local inbox_path
  if (cfg.nvim_inbox_file and (cfg.nvim_inbox_file ~= "")) then
    inbox_path = expand_path(cfg.nvim_inbox_file)
  else
    if (project and project["default-file"]) then
      inbox_path = project["default-file"]
    else
      local base = expand_path(cfg.data_dir)
      inbox_path = (base .. "/" .. cfg.default_file)
    end
  end
  return vim.cmd(("edit " .. inbox_path))
end
M["open-dir"] = function()
  local project = discover_project(config.project_files)
  if (project and project["default-file"]) then
    return vim.cmd(("edit " .. project["default-file"]))
  else
    local cwd = vim.fn.getcwd()
    local actions_files = vim.fn.glob((cwd .. "/*.actions"), true, true)
    if (#actions_files > 0) then
      return vim.cmd(("edit " .. actions_files[1]))
    else
      return vim.notify("No .actions file found in current directory", vim.log.levels.WARN)
    end
  end
end
M["setup-lsp"] = function(group)
  local bin = get_bin_path()
  if (config.nvim_lsp_enable and bin) then
    local function _66_(args)
      local project = discover_project(config.project_files)
      local root = ((project and project.root) or vim.fs.dirname(args.file) or vim.fn.getcwd())
      return vim.lsp.start({name = "clearhead-lsp", cmd = {bin, "lsp"}, root_dir = root})
    end
    return vim.api.nvim_create_autocmd("FileType", {pattern = "actions", group = group, callback = _66_})
  else
    if (config.nvim_lsp_enable and not bin) then
      return vim.notify("clearhead_cli binary not found. LSP disabled. Install with 'cargo install --path .' in the CLI directory.", vim.log.levels.WARN)
    else
      return nil
    end
  end
end
M.setup = function(opts)
  do
    local ctx = load_config_internal(opts)
    config = ctx.config
  end
  local group = vim.api.nvim_create_augroup("clearhead", {clear = true})
  M["setup-lsp"](group)
  if config.nvim_format_on_save then
    local function _69_()
      return M.format()
    end
    vim.api.nvim_create_autocmd("BufWritePre", {pattern = "*.actions", group = group, callback = _69_})
  else
  end
  local function _71_()
    vim.opt_local.conceallevel = 2
    vim.opt_local.concealcursor = "nc"
    if config.nvim_default_mappings then
      local opts0 = {buffer = true}
      vim.keymap.set("n", "<localleader><space>", M["cycle-state"], vim.tbl_extend("force", opts0, {desc = "Cycle action state"}))
      vim.keymap.set("n", "<localleader>f", M.format, vim.tbl_extend("force", opts0, {desc = "Format action file"}))
      vim.keymap.set("n", "<localleader>i", M["open-inbox"], vim.tbl_extend("force", opts0, {desc = "Open inbox"}))
      vim.keymap.set("n", "<localleader>p", M["open-dir"], vim.tbl_extend("force", opts0, {desc = "Open project file"}))
      vim.keymap.set("n", "<localleader>a", M.archive, vim.tbl_extend("force", opts0, {desc = "Archive completed actions"}))
      vim.keymap.set("n", "<localleader>o", M["smart-new-action"], vim.tbl_extend("force", opts0, {desc = "New action below"}))
      vim.keymap.set("n", "<localleader>x", M["set-state"]("x"), vim.tbl_extend("force", opts0, {desc = "Set state to Completed"}))
      vim.keymap.set("n", "<localleader>-", M["set-state"]("-"), vim.tbl_extend("force", opts0, {desc = "Set state to In Progress"}))
      vim.keymap.set("n", "<localleader>=", M["set-state"]("="), vim.tbl_extend("force", opts0, {desc = "Set state to Blocked"}))
      return vim.keymap.set("n", "<localleader>_", M["set-state"]("_"), vim.tbl_extend("force", opts0, {desc = "Set state to Cancelled"}))
    else
      return nil
    end
  end
  vim.api.nvim_create_autocmd("FileType", {pattern = "actions", group = group, callback = _71_})
  vim.api.nvim_create_user_command("ClearheadInbox", M["open-inbox"], {})
  return vim.api.nvim_create_user_command("ClearheadOpenDir", M["open-dir"], {})
end
return M
