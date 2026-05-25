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

local function signature_for(bin, data_dir, folders)
	local parts = { tostring(config.values.nvim_lsp_enable), bin or "", data_dir or "" }
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

	local bin = config.get_bin_path()
	if not bin then
		if not M.missing_bin_notified then
			vim.notify(
				"clearhead binary not found. LSP disabled. Install with 'cargo install --path .' in the CLI directory.",
				vim.log.levels.WARN
			)
			M.missing_bin_notified = true
		end
		return false
	end

	M.missing_bin_notified = false
	local data_dir = config.expand_path(config.values.data_dir)
	local workspace_folders = build_workspace_folders()
	local signature = signature_for(bin, data_dir, workspace_folders)
	if M.configured_signature == signature then
		return true
	end

	vim.lsp.config("clearhead-lsp", {
		cmd = { bin, "start", "lsp" },
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
