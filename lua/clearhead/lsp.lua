local config = require("clearhead.config")

local M = {
	configured_signature = nil,
	missing_bin_notified = false,
}

local function build_workspace_folders()
	local folders = {}
	local data_dir = config.expand_path(config.values.data_dir)
	if data_dir and data_dir ~= "" then
		table.insert(folders, {
			uri = vim.uri_from_fname(data_dir),
			name = vim.fn.fnamemodify(data_dir, ":t"),
		})
	end
	for _, path in ipairs(config.values.additional_workspaces or {}) do
		local expanded = vim.fn.expand(path)
		table.insert(folders, {
			uri = vim.uri_from_fname(expanded),
			name = vim.fn.fnamemodify(expanded, ":t"),
		})
	end
	return folders
end

local function signature_for(command, data_dir, folders)
	local parts = { tostring(config.values.nvim_lsp_enable), table.concat(command or {}, "\0"), data_dir or "" }
	for _, folder in ipairs(folders) do
		parts[#parts + 1] = folder.name .. "=" .. folder.uri
	end
	return table.concat(parts, "\n")
end

-- Registers or refreshes the server profile using the current config.
-- Safe to call repeatedly from ftplugin startup and setup() overrides.
M.setup = function()
	if not config.values.nvim_lsp_enable then
		return false
	end

	local command, legacy = config.get_lsp_command()
	if not command then
		if not M.missing_bin_notified then
			vim.notify(
				"clearhead-lsp not found. Install the standalone server or set nvim_lsp_binary_path.",
				vim.log.levels.WARN
			)
			M.missing_bin_notified = true
		end
		return false
	end

	M.missing_bin_notified = false
	local data_dir = config.expand_path(config.values.data_dir)
	local workspace_folders = build_workspace_folders()
	local signature = signature_for(command, data_dir, workspace_folders)
	if M.configured_signature == signature then
		return true
	end
	if legacy then
		vim.notify("Using legacy 'clearhead start lsp' fallback; install clearhead-lsp.", vim.log.levels.WARN)
	end

	vim.lsp.config("clearhead-lsp", {
		cmd = command,
		filetypes = { "actions" },
		-- Stable root_dir = one server instance across all workspaces.
		root_dir = function(_, on_dir)
			on_dir(data_dir)
		end,
		workspace_folders = workspace_folders,
	})

	vim.lsp.enable("clearhead-lsp")
	M.configured_signature = signature
	return true
end

return M
