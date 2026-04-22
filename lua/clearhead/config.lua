local M = {}

local DEFAULTS = {
	data_dir = "",
	config_dir = "",
	default_file = "inbox.actions",
	nvim_auto_normalize = true,
	nvim_format_on_save = true,
	nvim_lsp_enable = true,
	nvim_inbox_file = "",
	nvim_lsp_binary_path = "",
	nvim_default_mappings = true,
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
		CLEARHEAD_NVIM_AUTO_NORMALIZE = "nvim_auto_normalize",
		CLEARHEAD_NVIM_FORMAT_ON_SAVE = "nvim_format_on_save",
		CLEARHEAD_NVIM_LSP_ENABLE = "nvim_lsp_enable",
		CLEARHEAD_NVIM_INBOX_FILE = "nvim_inbox_file",
		CLEARHEAD_NVIM_LSP_BINARY_PATH = "nvim_lsp_binary_path",
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

M.get_bin_path = function()
	if M.values.nvim_lsp_binary_path and M.values.nvim_lsp_binary_path ~= "" then
		local expanded = expand_path(M.values.nvim_lsp_binary_path)
		return vim.fn.executable(expanded) == 1 and expanded or nil
	end
	if vim.fn.executable("clearhead_cli") == 1 then
		return "clearhead_cli"
	end
	local cargo_bin = vim.fn.expand("~") .. "/.cargo/bin/clearhead_cli"
	return vim.fn.executable(cargo_bin) == 1 and cargo_bin or nil
end

return M
