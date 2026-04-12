local M = {}

-- Forward declarations — allows newspaper ordering (public API first, helpers below)
local config
local expand_path, get_default_config_dir, get_default_data_dir
local load_env, read_json_file, load_config_internal
local get_bin_path, get_action_state_node, attach_lsp, setup_lsp
local maybe_add_completion_date, on_output

-- =============================================================================
-- Constants
-- =============================================================================

local DEFAULTS = {
  data_dir              = "",
  config_dir            = "",
  default_file          = "inbox.actions",
  nvim_auto_normalize   = true,
  nvim_format_on_save   = true,
  nvim_lsp_enable       = true,
  nvim_inbox_file       = "",
  nvim_lsp_binary_path  = "",
  nvim_default_mappings = true,
}

-- Treesitter query shared by get_action_state_node and get_status
local STATE_QUERY = [[((state [
  (state_not_started)
  (state_completed)
  (state_in_progress)
  (state_blocked)
  (state_cancelled)
] @val))]]

local state_cycle = { " ", "-", "=", "x", "_" }

-- Runtime config — mutated by setup()
config = vim.deepcopy(DEFAULTS)

-- =============================================================================
-- Public API
-- =============================================================================

M.setup = function(opts)
  config = load_config_internal(opts).config

  local group = vim.api.nvim_create_augroup("clearhead", { clear = true })
  setup_lsp(group)

  if config.nvim_format_on_save then
    vim.api.nvim_create_autocmd("BufWritePre", {
      pattern = "*.actions",
      group = group,
      callback = function() M.format() end,
    })
  end

  vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
    pattern = "*.actions",
    group = group,
    callback = function()
      if vim.fn.mode() == "n" and vim.fn.bufname() ~= "" then
        vim.cmd("checktime")
      end
    end,
  })

  vim.api.nvim_create_autocmd("FileChangedShellPost", {
    pattern = "*.actions",
    group = group,
    callback = function()
      vim.notify("File updated from disk.", vim.log.levels.INFO)
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "actions",
    group = group,
    callback = function(args)
      vim.opt_local.autoread = true
      vim.opt_local.conceallevel = 2
      vim.opt_local.concealcursor = "nc"
      attach_lsp(args.buf)

      if config.nvim_default_mappings then
        local function map(key, fn, desc)
          vim.keymap.set("n", key, fn, { buffer = true, desc = desc })
        end
        map("<localleader><space>", M.cycle_state,       "Cycle action state")
        map("<localleader>f",       M.format,            "Format action file")
        map("<localleader>i",       M.open_inbox,        "Open inbox")
        map("<localleader>p",       M.open_workspace,    "Browse workspace")
        map("<localleader>a",       M.archive,           "Archive completed actions")
        map("<localleader>o",       M.smart_new_action,  "New action below")
        map("<localleader>x",       M.set_state("x"), "Set state to Completed")
        map("<localleader>-",       M.set_state("-"), "Set state to In Progress")
        map("<localleader>=",       M.set_state("="), "Set state to Blocked")
        map("<localleader>_",       M.set_state("_"), "Set state to Cancelled")
        map("<localleader><bs>",    M.set_state(" "), "Set state to Not Started")
      end
    end,
  })

  vim.api.nvim_create_user_command("ClearheadInbox",     M.open_inbox, {})
  vim.api.nvim_create_user_command("ClearheadWorkspace", M.open_workspace, {})
  vim.api.nvim_create_user_command("ClearheadDiff", function()
    vim.cmd("vertical diffsplit %")
  end, {})
end

M.archive = function()
  local bufnr = vim.api.nvim_get_current_buf()
  if #vim.lsp.get_clients({ name = "clearhead-lsp", bufnr = bufnr }) > 0 then
    vim.lsp.buf.execute_command({
      command = "clearhead/archive",
      arguments = { vim.uri_from_bufnr(bufnr) },
    })
    return
  end

  -- Fallback: invoke CLI directly when LSP isn't running
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local bin = get_bin_path()
  if filename == "" or not bin then
    vim.notify("Cannot archive: buffer has no file or CLI not found.", vim.log.levels.ERROR)
    return
  end

  vim.cmd("write")
  vim.fn.jobstart({ bin, "archive", "plans", filename }, {
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        vim.schedule(function()
          vim.api.nvim_command("edit!")
          vim.notify("Archived completed actions.")
        end)
      else
        vim.notify("Archive failed.", vim.log.levels.ERROR)
      end
    end,
    on_stdout = on_output(nil),
    on_stderr = on_output("Archive error: "),
  })
end

M.format = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local attached = vim.lsp.get_clients({ name = "clearhead-lsp", bufnr = bufnr })

  if #attached > 0 then
    vim.lsp.buf.format({ name = "clearhead-lsp", bufnr = bufnr })
    return
  end

  -- LSP is running but not attached to this buffer yet — attach then format
  if #vim.lsp.get_clients({ name = "clearhead-lsp" }) > 0 then
    attach_lsp(bufnr)
    vim.schedule(function()
      vim.lsp.buf.format({ name = "clearhead-lsp", bufnr = bufnr })
    end)
    return
  end

  if config.nvim_auto_normalize then
    M.normalize(bufnr)
  end
end

M.normalize = function(bufnr)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local bin = get_bin_path()
  if filename == "" or not bin then return end

  vim.fn.jobstart({ bin, "normalize", "file", filename, "--write" }, {
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        vim.schedule(function() vim.api.nvim_command("checktime") end)
      end
    end,
    on_stderr = on_output("clearhead_cli normalize error: "),
  })
end

M.cycle_state = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local linenr = vim.fn.line(".") - 1
  local node = get_action_state_node(bufnr, linenr)
  if not node then
    vim.notify("No action state found on this line", vim.log.levels.WARN)
    return
  end

  local current = vim.treesitter.get_node_text(node, bufnr)
  local next_state = state_cycle[1]
  for i, state in ipairs(state_cycle) do
    if state == current then
      next_state = state_cycle[(i % #state_cycle) + 1]
      break
    end
  end

  local srow, scol, erow, ecol = node:range()
  vim.api.nvim_buf_set_text(bufnr, srow, scol, erow, ecol, { next_state })

  if next_state == "x" then
    maybe_add_completion_date(bufnr, linenr)
  end
end

M.set_state = function(state)
  return function()
    local bufnr = vim.api.nvim_get_current_buf()
    local linenr = vim.fn.line(".") - 1
    local node = get_action_state_node(bufnr, linenr)
    if not node then
      vim.notify("No action state found on this line", vim.log.levels.WARN)
      return
    end

    local srow, scol, erow, ecol = node:range()
    vim.api.nvim_buf_set_text(bufnr, srow, scol, erow, ecol, { state })

    if state == "x" then
      maybe_add_completion_date(bufnr, linenr)
    end
  end
end

M.smart_new_action = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local linenr = vim.fn.line(".") - 1
  local root = vim.treesitter.get_parser(bufnr, "actions"):parse()[1]:root()
  local node = root:named_descendant_for_range(linenr, 0, linenr, -1)

  local depth_markers = ""
  local current = node
  while current do
    local kind = current:type()
    if kind:find("depth(%d)_action") then
      depth_markers = string.rep(">", tonumber(kind:match("depth(%d)_action")))
      break
    end
    current = current:parent()
  end

  local line = vim.fn.getline(linenr + 1)
  local indent = line:match("^(%s*)")
  local prefix = indent .. depth_markers .. (depth_markers ~= "" and " " or "")

  vim.fn.append(linenr + 1, prefix .. "[ ]  ^" .. vim.fn.strftime("%Y-%m-%dT%H:%M"))
  vim.fn.cursor(linenr + 2, #(prefix .. "[ ] ") + 1)
  vim.cmd("startinsert!")
end

M.get_status = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local ok = pcall(vim.treesitter.get_parser, bufnr, "actions")
  if not ok then return "" end

  local root = vim.treesitter.get_parser(bufnr, "actions"):parse()[1]:root()
  local query = vim.treesitter.query.parse("actions", STATE_QUERY)
  local total, completed = 0, 0

  for _, node in query:iter_captures(root, bufnr, 0, -1) do
    total = total + 1
    if vim.treesitter.get_node_text(node, bufnr) == "x" then
      completed = completed + 1
    end
  end

  return total > 0 and ("✓ " .. completed .. "/" .. total) or ""
end

M.open_inbox = function()
  local cfg = load_config_internal().config
  local inbox_path
  if cfg.nvim_inbox_file and cfg.nvim_inbox_file ~= "" then
    inbox_path = expand_path(cfg.nvim_inbox_file)
  else
    inbox_path = expand_path(cfg.data_dir) .. "/" .. cfg.default_file
  end
  vim.cmd("edit " .. inbox_path)
end

M.open_workspace = function()
  vim.cmd("edit " .. expand_path(config.data_dir))
end

M.get_conform_opts = function()
  return {
    formatters_by_ft = { actions = { "clearhead_cli" } },
    formatters = {
      clearhead_cli = {
        command = "clearhead_cli",
        args    = { "format", "file", "$FILENAME" },
        stdin   = false,
      },
    },
  }
end

-- =============================================================================
-- LSP helpers
-- =============================================================================

attach_lsp = function(bufnr)
  local bin = get_bin_path()
  if not config.nvim_lsp_enable or not bin then return end
  vim.lsp.start(
    { name = "clearhead-lsp", cmd = { bin, "start", "lsp" }, root_dir = expand_path(config.data_dir) },
    { bufnr = bufnr }
  )
end

setup_lsp = function(group)
  local bin = get_bin_path()
  if config.nvim_lsp_enable and bin then
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "actions",
      group = group,
      callback = function(args) attach_lsp(args.buf) end,
    })
  elseif config.nvim_lsp_enable then
    vim.notify(
      "clearhead_cli binary not found. LSP disabled. Install with 'cargo install --path .' in the CLI directory.",
      vim.log.levels.WARN
    )
  end
end

get_bin_path = function()
  if config.nvim_lsp_binary_path and config.nvim_lsp_binary_path ~= "" then
    local expanded = expand_path(config.nvim_lsp_binary_path)
    return vim.fn.executable(expanded) == 1 and expanded or nil
  end
  if vim.fn.executable("clearhead_cli") == 1 then return "clearhead_cli" end
  local cargo_bin = vim.fn.expand("~") .. "/.cargo/bin/clearhead_cli"
  return vim.fn.executable(cargo_bin) == 1 and cargo_bin or nil
end

-- =============================================================================
-- Treesitter helpers
-- =============================================================================

get_action_state_node = function(bufnr, linenr)
  local ok = pcall(vim.treesitter.get_parser, bufnr, "actions")
  if not ok then return nil end

  local root = vim.treesitter.get_parser(bufnr, "actions"):parse()[1]:root()
  local query = vim.treesitter.query.parse("actions", STATE_QUERY)
  local found = nil
  for _, node in query:iter_captures(root, bufnr, linenr, linenr + 1) do
    found = node
  end
  return found
end

-- Appends a completion timestamp to the current line if one isn't already present
maybe_add_completion_date = function(bufnr, linenr)
  local line = vim.fn.getline(linenr + 1)
  if not line:find("%%[0-9]") then
    vim.fn.setline(linenr + 1, line .. " %" .. vim.fn.strftime("%Y-%m-%dT%H:%M"))
  end
end

-- =============================================================================
-- Config loading
-- =============================================================================

expand_path = function(path)
  return (path and path ~= "") and vim.fn.expand(path) or path
end

get_default_config_dir = function()
  local xdg = os.getenv("XDG_CONFIG_HOME")
  return ((xdg and xdg ~= "") and xdg or (vim.fn.expand("~") .. "/.config")) .. "/clearhead"
end

get_default_data_dir = function()
  local xdg = os.getenv("XDG_DATA_HOME")
  return ((xdg and xdg ~= "") and xdg or (vim.fn.expand("~") .. "/.local/share")) .. "/clearhead"
end

read_json_file = function(path)
  if not (path and vim.fn.filereadable(path) == 1) then return {} end
  local content = table.concat(vim.fn.readfile(path), "")
  return (content ~= "") and vim.fn.json_decode(content) or {}
end

load_env = function()
  local env_map = {
    CLEARHEAD_DATA_DIR              = "data_dir",
    CLEARHEAD_CONFIG_DIR            = "config_dir",
    CLEARHEAD_DEFAULT_FILE          = "default_file",
    CLEARHEAD_NVIM_AUTO_NORMALIZE   = "nvim_auto_normalize",
    CLEARHEAD_NVIM_FORMAT_ON_SAVE   = "nvim_format_on_save",
    CLEARHEAD_NVIM_LSP_ENABLE       = "nvim_lsp_enable",
    CLEARHEAD_NVIM_INBOX_FILE       = "nvim_inbox_file",
    CLEARHEAD_NVIM_LSP_BINARY_PATH  = "nvim_lsp_binary_path",
    CLEARHEAD_NVIM_DEFAULT_MAPPINGS = "nvim_default_mappings",
  }
  local out = {}
  for env_var, key in pairs(env_map) do
    local val = os.getenv(env_var)
    if val and val ~= "" then
      if val == "true" or val == "false" then
        out[key] = (val == "true")
      elseif tonumber(val) then
        out[key] = tonumber(val)
      elseif val:find("^%[") and val:find("%]$") then
        out[key] = vim.fn.json_decode(val)
      else
        out[key] = val
      end
    end
  end
  return out
end

-- Merges config from all sources: defaults → global config file → env vars → user opts
-- Precedence: user_opts > env > config file > defaults
load_config_internal = function(user_opts)
  local config_dir = get_default_config_dir()
  local merged = vim.tbl_extend("force",
    DEFAULTS,
    read_json_file(config_dir .. "/config.json"),
    load_env(),
    user_opts or {}
  )
  merged.config_dir = (merged.config_dir == "" or not merged.config_dir)
    and config_dir or expand_path(merged.config_dir)
  merged.data_dir = (merged.data_dir == "" or not merged.data_dir)
    and get_default_data_dir() or expand_path(merged.data_dir)
  return { config = merged }
end

-- =============================================================================
-- Misc helpers
-- =============================================================================

-- Returns a job output handler; prefix is prepended and level set to ERROR when present
on_output = function(prefix)
  return function(_, data)
    if not (data and #data > 0) then return end
    local msg = table.concat(data, "\n")
    if msg == "" or msg:find("^%s*$") then return end
    if prefix then
      vim.notify(prefix .. msg, vim.log.levels.ERROR)
    else
      vim.notify(msg)
    end
  end
end

-- =============================================================================
-- Test exports — defined last so helpers are fully initialised
-- =============================================================================

M._testing = { ["load-config-internal"] = load_config_internal }

return M
