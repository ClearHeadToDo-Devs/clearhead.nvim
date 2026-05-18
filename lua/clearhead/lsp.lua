local config = require("clearhead.config")

local M = {}

local binary_warned = false

M.attach = function(bufnr)
	if not config.values.nvim_lsp_enable then
		return
	end
	local bin = config.get_bin_path()
	if not bin then
		if not binary_warned then
			binary_warned = true
			vim.notify(
				"clearhead binary not found. LSP disabled. Install with 'cargo install --path .' in the CLI directory.",
				vim.log.levels.WARN
			)
		end
		return
	end
	vim.lsp.start(
		{ name = "clearhead-lsp", cmd = { bin, "start", "lsp" }, root_dir = config.expand_path(config.values.data_dir) },
		{ bufnr = bufnr }
	)
end

return M
