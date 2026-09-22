local assert = require("luassert")

local config = require("clearhead.config")
local quick_add = require("clearhead.quick_add")

describe("quick add", function()
	local original_values

	before_each(function()
		original_values = vim.deepcopy(config.values)
		config.values.nvim_indent_style = "spaces"
		config.values.nvim_indent_width = 2
	end)

	after_each(function()
		config.values = original_values
	end)

	it("turns an indented outline into an action subtree", function()
		local lines, err = quick_add.compile({
			"Ship release",
			"  - Run tests",
			"    Publish package",
			"  Announce",
		}, 2)

		assert.is_nil(err)
		assert.are.same({
			"[ ] Ship release",
			"  >[ ] Run tests",
			"    >>[ ] Publish package",
			"  >[ ] Announce",
		}, lines)
	end)

	it("ignores blank lines and accepts a uniformly indented paste", function()
		local lines = assert(quick_add.compile({ "", "    Parent", "      Child", "" }, 2))
		assert.are.same({ "[ ] Parent", "  >[ ] Child" }, lines)
	end)

	it("rejects misaligned and skipped depths", function()
		local _, misaligned = quick_add.compile({ "Parent", " Child" }, 2)
		assert.matches("not aligned", misaligned)

		local _, skipped = quick_add.compile({ "Parent", "    Grandchild" }, 2)
		assert.matches("skips an action depth", skipped)
	end)

	it("appends captures to an unloaded inbox", function()
		local tmp = vim.fn.tempname()
		local path = tmp .. "/charters/inbox.actions"
		vim.fn.mkdir(tmp .. "/charters", "p")
		vim.fn.writefile({ "[ ] Existing" }, path)

		local ok, err = quick_add.append(path, { "[ ] Parent", "  >[ ] Child" })
		assert.is_true(ok, err)
		assert.are.same({ "[ ] Existing", "[ ] Parent", "  >[ ] Child" }, vim.fn.readfile(path))
	end)

	it("refuses to overwrite a modified loaded inbox", function()
		local tmp = vim.fn.tempname()
		local path = tmp .. "/inbox.actions"
		vim.fn.mkdir(tmp, "p")
		vim.fn.writefile({ "[ ] Existing" }, path)
		local bufnr = vim.fn.bufadd(path)
		vim.fn.bufload(bufnr)
		vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "[ ] Unsaved" })

		local ok, err = quick_add.append(path, { "[ ] New" })
		assert.is_nil(ok)
		assert.matches("save the modified inbox", err)
		assert.are.same({ "[ ] Existing" }, vim.fn.readfile(path))
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end)
end)
