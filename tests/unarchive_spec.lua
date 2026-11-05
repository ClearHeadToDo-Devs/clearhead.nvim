local assert = require("luassert")
local clearhead = require("clearhead")
local command = require("clearhead.command")
local config = require("clearhead.config")

describe("unarchive", function()
	local root, active, completed, original_bin, original_values, original_system, notices

	before_each(function()
		vim.cmd("silent! %bwipeout!")
		root = vim.fn.tempname()
		vim.fn.mkdir(root .. "/.clearhead/charters", "p")
		active = root .. "/.clearhead/charters/home.actions"
		completed = root .. "/.clearhead/charters/home.completed.actions"
		vim.fn.writefile({ "[ ] Keep" }, active)
		vim.fn.writefile({ "[x] History" }, completed)
		original_bin, original_system = config.get_bin_path, vim.system
		original_values = vim.deepcopy(config.values)
		clearhead._testing["load-config-internal"]({
			nvim_archive_on_save = true,
			nvim_auto_normalize = false,
			nvim_format_on_save = false,
			nvim_lsp_enable = false,
		})
		clearhead._testing["plugin-init"]()
		config.get_bin_path = function()
			return "clearhead"
		end
		notices = {}
		stub(vim, "notify", function(msg)
			notices[#notices + 1] = msg
		end)
		vim.cmd("edit " .. vim.fn.fnameescape(completed))
		vim.bo.autoread = true
	end)

	after_each(function()
		config.get_bin_path, vim.system = original_bin, original_system
		clearhead._testing["load-config-internal"](original_values)
		vim.notify:revert()
		vim.cmd("silent! %bwipeout!")
		vim.fn.delete(root, "rf")
	end)

	it("dispatches and forwards CLI arguments from the current buffer's workspace", function()
		local captured
		vim.system = function(cmd, opts)
			captured = { cmd = cmd, opts = opts }
			return { wait = function()
				return { code = 0, stdout = "Unarchived", stderr = "" }
			end }
		end
		local args = { "target", "--reopen", "--cascade", "--charter", "home", "--dry-run" }
		local leaf, rest = command.resolve(command.tree, vim.list_extend({ "unarchive", "action" }, args))
		leaf.run(rest)
		assert.are.same(vim.list_extend({ "clearhead", "unarchive", "action" }, args), captured.cmd)
		assert.are.equal(root, captured.opts.cwd)
		assert.are.equal("Unarchived", notices[1])
		assert.are.same({ "action" }, command.complete(command.tree, "", "Clearhead unarchive "))
		assert.are.same({ "--cascade" }, command.complete(command.tree, "--cas", "Clearhead unarchive action target --cas"))
	end)

	it("refuses unsaved source or destination buffers without running the CLI", function()
		vim.system = function()
			error("must not run under unsaved action buffers")
		end
		for _, path in ipairs({ completed, active }) do
			vim.cmd("edit " .. vim.fn.fnameescape(path))
			vim.api.nvim_buf_set_lines(0, -1, -1, false, { "[ ] Unsaved" })
			assert.is_nil(clearhead.unarchive({ "target" }))
			assert.is_truthy(notices[#notices]:find("save " .. path, 1, true))
			vim.bo.modified = false
		end
	end)

	it("reports CLI refusal without reloading or changing either file", function()
		vim.system = function()
			return { wait = function()
				return { code = 1, stdout = "", stderr = "not a root; unarchive root-id instead" }
			end }
		end
		assert.is_nil(clearhead.unarchive({ "child" }))
		assert.is_truthy(notices[1]:find("root-id", 1, true))
		assert.are.same({ "[x] History" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
		assert.are.same({ "[ ] Keep" }, vim.fn.readfile(active))
	end)

	it("moves without saving, then sweeps back on save unless reopened", function()
		if vim.fn.executable("clearhead") == 0 then
			pending("clearhead is not available on PATH")
			return
		end
		local id = "01951111-0000-7000-8000-000000000061"
		local tree = {
			"[x] Root %2020-01-01T00:00 #" .. id,
			">[_] Child %2020-02-02T00:00 #01951111-0000-7000-8000-000000000062",
		}
		vim.fn.writefile(tree, completed)
		vim.cmd("edit!")
		local history_buf = vim.api.nvim_get_current_buf()
		vim.cmd("edit " .. vim.fn.fnameescape(active))
		local active_buf = vim.api.nvim_get_current_buf()
		vim.bo.autoread = true
		vim.cmd("buffer " .. history_buf)
		local function disk(path)
			return table.concat(vim.fn.readfile(path), "\n")
		end
		local function unarchive(flags)
			local args = vim.list_extend({ id, "--file", active }, flags or {})
			assert.is_true(clearhead.unarchive(args), table.concat(notices, "\n"))
		end

		unarchive()
		assert.is_truthy(disk(active):find("[x] Root", 1, true))
		assert.is_falsy(disk(completed):find(id, 1, true))
		assert.is_falsy(table.concat(vim.api.nvim_buf_get_lines(history_buf, 0, -1, false), "\n"):find(id, 1, true))
		vim.cmd("buffer " .. active_buf)
		assert.is_truthy(table.concat(vim.api.nvim_buf_get_lines(active_buf, 0, -1, false), "\n"):find(id, 1, true))
		vim.cmd("write")
		assert.is_falsy(disk(active):find(id, 1, true))
		assert.is_truthy(disk(completed):find("[_] Child %2020-02-02T00:00", 1, true))

		unarchive({ "--reopen" })
		assert.is_truthy(disk(active):find("[ ] Root", 1, true))
		assert.is_truthy(disk(active):find("[_] Child %2020-02-02T00:00", 1, true))
		assert.is_falsy(disk(active):find("%2020-01-01T00:00", 1, true))
		vim.cmd("write")
		assert.is_truthy(disk(active):find(id, 1, true))

		-- Return the original closed tree to history to exercise the composed flags.
		vim.fn.writefile({ "[ ] Keep" }, active)
		vim.fn.writefile(tree, completed)
		vim.cmd("checktime")
		unarchive({ "--reopen", "--cascade" })
		assert.is_truthy(disk(active):find("[ ] Root", 1, true))
		assert.is_truthy(disk(active):find("[ ] Child", 1, true))
		assert.is_falsy(disk(active):find("%2020", 1, true))
	end)
end)
