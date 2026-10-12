local config = require("clearhead.config")

local M = {}

local check_neovim, check_cli, check_treesitter, check_config, check_modules

-- =============================================================================
-- Public API
-- =============================================================================

M.check = function()
  check_neovim()
  check_modules()
  check_cli()
  check_treesitter()
  check_config()
end

-- =============================================================================
-- Checks
-- =============================================================================

check_neovim = function()
  vim.health.start("clearhead: Neovim")
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim >= 0.10")
  else
    vim.health.error("Neovim >= 0.10 required", "Upgrade Neovim")
  end
end

-- The feature modules are loaded lazily (required on first use), which means a
-- broken module would otherwise stay silent until someone triggered its
-- feature. Requiring each one here surfaces load/syntax errors up front.
check_modules = function()
  vim.health.start("clearhead: Modules")
  -- The module set is derived from clearhead's lazy_exports, so this check can
  -- never fall out of sync with what the plugin actually loads on demand.
  for _, name in ipairs(require("clearhead")._feature_modules) do
    local ok, err = pcall(require, name)
    if ok then
      vim.health.ok(name .. " loads")
    else
      vim.health.error(name .. " failed to load", tostring(err))
    end
  end
end

check_cli = function()
  vim.health.start("clearhead: CLI binary")
  local bin = config.get_bin_path()
  if not bin then
    vim.health.error(
      "clearhead not found",
      "Run: cargo install --path . inside clearhead-cli/"
    )
    return
  end

  local version = vim.fn.system({ bin, "--version" }):gsub("%s+$", "")
  if vim.v.shell_error == 0 then
    vim.health.ok(version .. " (" .. bin .. ")")
  else
    vim.health.warn("Binary found but --version failed", bin)
  end
end

-- The grammar's own version (tree-sitter.json), or nil for a grammar built
-- before ABI 15 or a Neovim too old to expose it.
local function grammar_version(info)
  local m = info.metadata
  return m and string.format("%d.%d.%d", m.major_version, m.minor_version, m.patch_version)
end

-- Queries nvim-treesitter installs alongside the parser from tree-sitter-actions.
local GRAMMAR_QUERIES = { "highlights", "folds", "indents" }

-- Compiles every query the plugin relies on against the installed parser. A
-- parser that drifted from its queries fails here instead of silently
-- breaking highlighting or state toggling.
local function check_queries()
  local compiled = {}
  local function check(name, compile)
    local ok, query = pcall(compile)
    if not ok then
      vim.health.error(name .. " query does not compile against the parser: " .. tostring(query), ":TSUpdate actions")
    elseif not query then
      vim.health.warn(name .. " query not found on the runtimepath", ":TSUpdate actions")
    else
      table.insert(compiled, name)
    end
  end

  for _, name in ipairs(GRAMMAR_QUERIES) do
    check(name, function()
      return vim.treesitter.query.get("actions", name)
    end)
  end
  check("state", function()
    return vim.treesitter.query.parse("actions", require("clearhead.actions").STATE_QUERY)
  end)

  if #compiled > 0 then
    vim.health.ok("queries: " .. table.concat(compiled, ", "))
  end
end

check_treesitter = function()
  vim.health.start("clearhead: Tree-sitter grammar")
  local ok, info = pcall(vim.treesitter.language.inspect, "actions")
  if not ok then
    vim.health.error("actions grammar not installed", ":TSInstall actions")
    return
  end

  local version = grammar_version(info)
  if version then
    vim.health.ok(string.format("parser grammar v%s (ABI %d)", version, info.abi_version))
  else
    vim.health.warn(
      "parser grammar does not report its version",
      "Run :TSUpdate actions (reading it needs an ABI 15 grammar and Neovim >= 0.12)"
    )
  end

  check_queries()
end

check_config = function()
  vim.health.start("clearhead: Config")

  local ok, clearhead = pcall(require, "clearhead")
  if not ok then
    vim.health.error("Failed to load clearhead module: " .. tostring(clearhead))
    return
  end

  local cfg = clearhead._testing["load-config-internal"]().config

  -- data_dir — required for LSP root and the default capture file (charters/next.actions)
  vim.health.info("data_dir: " .. (cfg.data_dir ~= "" and cfg.data_dir or "(not set)"))
  if cfg.data_dir ~= "" and vim.fn.isdirectory(cfg.data_dir) == 1 then
    vim.health.ok("data_dir exists")
  elseif cfg.data_dir ~= "" then
    vim.health.warn("data_dir is set but does not exist yet (will be created on first use)")
  else
    vim.health.warn("data_dir not configured", "Set CLEARHEAD_DATA_DIR or pass data_dir to setup()")
  end

  -- config_dir — optional, only needed for config.json
  vim.health.info("config_dir: " .. cfg.config_dir)
  if vim.fn.isdirectory(cfg.config_dir) == 1 then
    vim.health.ok("config_dir exists")
  else
    vim.health.info("config_dir not found (optional — no config.json will be loaded)")
  end

  -- LSP
  if cfg.nvim_lsp_enable then
    local command, legacy = config.get_lsp_command()
    if command and not legacy then
      vim.health.ok("LSP enabled and standalone clearhead-lsp found")
    elseif command then
      vim.health.warn(
        "LSP is using the legacy clearhead start lsp fallback",
        "Install clearhead-lsp or set nvim_lsp_binary_path in setup()"
      )
    else
      vim.health.error(
        "LSP enabled but clearhead-lsp was not found",
        "Install clearhead-lsp or set nvim_lsp_binary_path in setup()"
      )
    end
  else
    vim.health.info("LSP disabled (nvim_lsp_enable = false)")
  end
end

return M
