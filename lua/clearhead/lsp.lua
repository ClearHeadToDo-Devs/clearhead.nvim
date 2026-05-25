local config = require("clearhead.config")

local M = {}

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

-- Called once from clearhead.setup() after config is loaded.
-- Registers the server profile and enables auto-attach on the actions filetype.
M.setup = function()
	if not config.values.nvim_lsp_enable then
		return
	end

	local bin = config.get_bin_path()
	if not bin then
		vim.notify(
			"clearhead binary not found. LSP disabled. Install with 'cargo install --path .' in the CLI directory.",
			vim.log.levels.WARN
		)
		return
	end

	local data_dir = config.expand_path(config.values.data_dir)

	vim.lsp.config("clearhead-lsp", {
		cmd = { bin, "start", "lsp" },
		filetypes = { "actions" },
		-- Stable root_dir = one server instance across all workspaces.
		root_dir = function(_, on_dir)
			on_dir(data_dir)
		end,
		workspace_folders = build_workspace_folders(),
	})

	vim.lsp.enable("clearhead-lsp")
end

return M
