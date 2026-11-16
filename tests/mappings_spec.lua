local assert = require("luassert")

describe("mappings", function()
	local clearhead = require("clearhead")
	local config = require("clearhead.config")
	local mappings = require("clearhead.mappings")
	local saved

	local function actions_buffer()
		local bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(bufnr)
		clearhead._setup_actions_buffer(bufnr)
		return bufnr
	end

	local function buffer_rhs(bufnr, lhs)
		return vim.api.nvim_buf_call(bufnr, function()
			return vim.fn.maparg(lhs, "n", false, true).rhs
		end)
	end

	before_each(function()
		saved = config.values
		config.values = vim.tbl_extend("force", saved, { nvim_lsp_enable = false, nvim_default_mappings = true })
		clearhead._plugin_init()
	end)

	after_each(function()
		config.values = saved
		pcall(vim.keymap.del, "n", "gX")
	end)

	it("defines a <Plug> mapping for every row", function()
		for _, rows in ipairs({ mappings.actions, mappings.charter, mappings.quickfix }) do
			for _, row in ipairs(rows) do
				assert.is_function(vim.fn.maparg(mappings.plug(row[1]), "n", false, true).callback)
			end
		end
	end)

	it("maps default keys onto <Plug> names in .actions buffers", function()
		local bufnr = actions_buffer()
		assert.are.equal("<Plug>(clearhead-complete)", buffer_rhs(bufnr, "<localleader>x"))
		assert.are.equal("<Plug>(clearhead-open-inbox)", buffer_rhs(bufnr, "<localleader>i"))
	end)

	it("skips a default when the user already maps its <Plug>", function()
		vim.keymap.set("n", "gX", "<Plug>(clearhead-complete)")
		local bufnr = actions_buffer()
		assert.is_nil(buffer_rhs(bufnr, "<localleader>x"))
		assert.are.equal("<Plug>(clearhead-cancel)", buffer_rhs(bufnr, "<localleader>_"))
	end)

	it("sets no default keys when nvim_default_mappings is false", function()
		config.values.nvim_default_mappings = false
		local bufnr = actions_buffer()
		assert.is_nil(buffer_rhs(bufnr, "<localleader>x"))
	end)

	it("gives quickfix rows no default key", function()
		for _, row in ipairs(mappings.quickfix) do
			assert.is_false(row[2])
		end
	end)

	it("refuses action edits outside an .actions buffer", function()
		local bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(bufnr)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = 1" })
		vim.bo[bufnr].filetype = "lua"
		local indent = vim.fn.maparg(mappings.plug("indent"), "n", false, true).callback
		indent()
		assert.are.same({ "local x = 1" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
	end)
end)

describe("open_project_root", function()
	it("finds the project from the window cwd, not the buffer path", function()
		local root = vim.fn.tempname()
		vim.fn.mkdir(root .. "/.clearhead/charters", "p")
		vim.fn.mkdir(root .. "/src", "p")
		local saved = vim.fn.getcwd()
		vim.cmd("enew")
		vim.cmd("lcd " .. vim.fn.fnameescape(root .. "/src"))
		require("clearhead").open_project_root(0)
		assert.are.equal(
			vim.uv.fs_realpath(root) .. "/.clearhead/charters/next.actions",
			vim.uv.fs_realpath(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":h")) .. "/next.actions"
		)
		vim.cmd("cd " .. vim.fn.fnameescape(saved))
	end)
end)
