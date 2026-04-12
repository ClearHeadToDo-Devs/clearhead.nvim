local M = {}

-- Forward declarations
local check_neovim, check_cli, check_treesitter, check_config
local find_cli_binary

-- =============================================================================
-- Public API
-- =============================================================================

M.check = function()
  check_neovim()
  check_cli()
  check_treesitter()
  check_config()
end

-- =============================================================================
-- Checks
-- =============================================================================

check_neovim = function()
  vim.health.start("clearhead: Neovim")
  if vim.fn.has("nvim-0.9") == 1 then
    vim.health.ok("Neovim >= 0.9")
  else
    vim.health.error("Neovim >= 0.9 required", "Upgrade Neovim")
  end
end

check_cli = function()
  vim.health.start("clearhead: CLI binary")
  local bin = find_cli_binary()
  if not bin then
    vim.health.error(
      "clearhead_cli not found",
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

check_treesitter = function()
  vim.health.start("clearhead: Tree-sitter grammar")
  local ok = pcall(vim.treesitter.language.inspect, "actions")
  if ok then
    vim.health.ok("actions grammar installed")
  else
    vim.health.error("actions grammar not installed", ":TSInstall actions")
  end
end

check_config = function()
  vim.health.start("clearhead: Config")

  local ok, clearhead = pcall(require, "clearhead")
  if not ok then
    vim.health.error("Failed to load clearhead module: " .. tostring(clearhead))
    return
  end

  local cfg = clearhead._testing["load-config-internal"]().config

  -- data_dir — required for LSP root and inbox
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
    local bin = find_cli_binary()
    if bin then
      vim.health.ok("LSP enabled and binary found")
    else
      vim.health.error(
        "LSP enabled but binary not found",
        "Install clearhead_cli or set nvim_lsp_binary_path in setup()"
      )
    end
  else
    vim.health.info("LSP disabled (nvim_lsp_enable = false)")
  end
end

-- =============================================================================
-- Helpers
-- =============================================================================

find_cli_binary = function()
  if vim.fn.executable("clearhead_cli") == 1 then return "clearhead_cli" end
  local cargo_bin = vim.fn.expand("~") .. "/.cargo/bin/clearhead_cli"
  return vim.fn.executable(cargo_bin) == 1 and cargo_bin or nil
end

return M
