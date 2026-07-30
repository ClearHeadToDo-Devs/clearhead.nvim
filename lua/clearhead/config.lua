local M = {}

local DEFAULTS = {
	data_dir = "",
	config_dir = "",
	default_file = "inbox.actions",
	additional_workspaces = {},
	nvim_auto_normalize = true,
	nvim_format_on_save = true,
	nvim_archive_on_save = false,
	nvim_lsp_enable = true,
	nvim_inbox_file = "",
	nvim_lsp_binary_path = "",
	nvim_graphd_binary_path = "",
	nvim_default_mappings = true,
	nvim_indent_style = "spaces",
	nvim_indent_width = 4,
}

M.values = vim.deepcopy(DEFAULTS)

local expand_path = function(path)
	return (path and path ~= "") and vim.fn.expand(path) or path
end

M.expand_path = expand_path

local function get_default_config_dir()
	local xdg = os.getenv("XDG_CONFIG_HOME")
	return ((xdg and xdg ~= "") and xdg or (vim.fn.expand("~") .. "/.config")) .. "/clearhead"
end

local function get_default_data_dir()
	local xdg = os.getenv("XDG_DATA_HOME")
	return ((xdg and xdg ~= "") and xdg or (vim.fn.expand("~") .. "/.local/share")) .. "/clearhead"
end

local function read_json_file(path)
	if not (path and vim.fn.filereadable(path) == 1) then
		return {}
	end
	local content = table.concat(vim.fn.readfile(path), "")
	return (content ~= "") and vim.fn.json_decode(content) or {}
end

local function load_env()
	local env_map = {
		CLEARHEAD_DATA_DIR = "data_dir",
		CLEARHEAD_CONFIG_DIR = "config_dir",
		CLEARHEAD_DEFAULT_FILE = "default_file",
		CLEARHEAD_ADDITIONAL_WORKSPACES = "additional_workspaces",
		CLEARHEAD_NVIM_AUTO_NORMALIZE = "nvim_auto_normalize",
		CLEARHEAD_NVIM_FORMAT_ON_SAVE = "nvim_format_on_save",
		CLEARHEAD_NVIM_ARCHIVE_ON_SAVE = "nvim_archive_on_save",
		CLEARHEAD_NVIM_LSP_ENABLE = "nvim_lsp_enable",
		CLEARHEAD_NVIM_INBOX_FILE = "nvim_inbox_file",
		CLEARHEAD_NVIM_LSP_BINARY_PATH = "nvim_lsp_binary_path",
		CLEARHEAD_NVIM_GRAPHD_BINARY_PATH = "nvim_graphd_binary_path",
		CLEARHEAD_NVIM_DEFAULT_MAPPINGS = "nvim_default_mappings",
		CLEARHEAD_NVIM_INDENT_STYLE = "nvim_indent_style",
		CLEARHEAD_NVIM_INDENT_WIDTH = "nvim_indent_width",
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

M.load = function(user_opts)
	local config_dir = get_default_config_dir()
	local merged =
		vim.tbl_extend("force", DEFAULTS, read_json_file(config_dir .. "/config.json"), load_env(), user_opts or {})
	merged.config_dir = (merged.config_dir == "" or not merged.config_dir) and config_dir
		or expand_path(merged.config_dir)
	merged.data_dir = (merged.data_dir == "" or not merged.data_dir) and get_default_data_dir()
		or expand_path(merged.data_dir)
	M.values = merged
	return merged
end

--- Resolve the synchronous ClearHead command client.
M.get_bin_path = function()
	if vim.fn.executable("clearhead") == 1 then
		return "clearhead"
	end
	local cargo_bin = vim.fn.expand("~") .. "/.cargo/bin/clearhead"
	return vim.fn.executable(cargo_bin) == 1 and cargo_bin or nil
end

--- Resolve graphd, the standalone query/read/export tool.
M.get_graphd_path = function()
	if M.values.nvim_graphd_binary_path and M.values.nvim_graphd_binary_path ~= "" then
		local expanded = expand_path(M.values.nvim_graphd_binary_path)
		return vim.fn.executable(expanded) == 1 and expanded or nil
	end
	if vim.fn.executable("clearhead-graphd") == 1 then
		return "clearhead-graphd"
	end
	local cargo_bin = vim.fn.expand("~") .. "/.cargo/bin/clearhead-graphd"
	return vim.fn.executable(cargo_bin) == 1 and cargo_bin or nil
end

--- Resolve the LSP process command. The standalone server is canonical; the
--- CLI subcommand is a temporary compatibility fallback during extraction.
--- Returns command argv and whether the legacy fallback was selected.
M.get_lsp_command = function()
	if M.values.nvim_lsp_binary_path and M.values.nvim_lsp_binary_path ~= "" then
		local expanded = expand_path(M.values.nvim_lsp_binary_path)
		return vim.fn.executable(expanded) == 1 and { expanded } or nil, false
	end
	if vim.fn.executable("clearhead-lsp") == 1 then
		return { "clearhead-lsp" }, false
	end
	local cargo_bin = vim.fn.expand("~") .. "/.cargo/bin/clearhead-lsp"
	if vim.fn.executable(cargo_bin) == 1 then
		return { cargo_bin }, false
	end
	local legacy = M.get_bin_path()
	return legacy and { legacy, "start", "lsp" } or nil, legacy ~= nil
end

return M
