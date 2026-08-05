# clearhead.nvim

Neovim plugin for the [ClearHead](https://github.com/ClearHeadToDo-Devs/clearhead-cli)
action management framework. Provides filetype support, LSP integration, and
editor-native commands for working with `.actions` files.

## Requirements

- Neovim 0.10+
- `nvim-treesitter` with the `actions` grammar installed
- `clearhead-lsp` on `PATH` (or set `nvim_lsp_binary_path`) for document intelligence
- `clearhead-graphd` on `PATH` (or set `nvim_graphd_binary_path`) for query views
- `clearhead` CLI for mutations such as complete, normalize, and archive

During the extraction transition, the plugin can temporarily fall back to
`clearhead start lsp` when the standalone server is unavailable.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "ClearHeadToDo-Devs/clearhead.nvim",
  ft = { "actions", "markdown" },
  cmd = {
    "ClearheadInbox",
    "ClearheadWorkspace",
    "ClearheadProjectRoot",
    "ClearheadDiff",
    "ClearheadArchiveWorkspace",
    "ClearheadPickActions",
    "ClearheadPickCharters",
    "ClearheadQuery",
    "ClearheadTree",
    "ClearheadGraph",
  },
}
```

The plugin works without calling `setup()`. Commands are registered from
`plugin/`, and buffer-local behavior is applied from `ftplugin/`.

Use `:ClearheadTree` for a graph-backed charter/action work map. The read-only
view opens source files with `<CR>`, toggles branches with `<Space>`, and
re-runs the tree query with `r`.

Use `:ClearheadGraph` for the dependency network as an actual DOT buffer. Press
`p` to render it to SVG through Graphviz, `r` to refresh, or edit/copy the DOT
with the normal Neovim ecosystem.

## Setup

`setup()` is optional and only needed when you want Lua-side overrides in
addition to the shared ClearHead config file and environment variables.

```lua
require("clearhead").setup({
  -- all options are optional; these are the defaults
  default_file          = "inbox.actions",
  additional_workspaces = {},        -- extra workspace roots to surface in pickers/LSP
  nvim_auto_normalize   = true,      -- assign missing UUIDs on save
  nvim_format_on_save   = true,      -- format via LSP on BufWritePre
  nvim_archive_on_save  = false,     -- move terminal actions after each save
  nvim_lsp_enable       = true,      -- auto-attach clearhead-lsp
  nvim_lsp_binary_path  = "",        -- explicit clearhead-lsp path (auto-detected)
  nvim_graphd_binary_path = "",      -- explicit clearhead-graphd path (auto-detected)
  nvim_inbox_file       = "",        -- override inbox path
  nvim_default_mappings = true,      -- enable <localleader> keybindings
  nvim_indent_style     = "spaces", -- buffer-local indent style for .actions
  nvim_indent_width     = 4,         -- buffer-local indent width for .actions
})
```

### Indentation and formatting

`clearhead.nvim` formats through the ClearHead LSP, and the LSP formatter
uses the current buffer indent options supplied by Neovim. To keep formatting
predictable, the plugin sets buffer-local defaults for `.actions` files:

- `expandtab = true`
- `shiftwidth = 4`
- `tabstop = 4`
- `softtabstop = 4`

You can override that behavior with `nvim_indent_style = "tabs"` or by
changing `nvim_indent_width` in `setup()` or `config.json`.

### Workspace discovery

The picker commands combine several sources:

- the user workspace (`data_dir`)
- any ancestor project workspaces discovered by walking up from the current buffer
- direct child repos inside an enclosing higher-order project workspace
- any `additional_workspaces` you configure explicitly

Picker file discovery is recursive under `charters/`, so nested charter
hierarchies are included instead of only top-level files.

For root-charter files like `charters/next.actions`, the picker shows the
workspace/project name rather than the literal directory name `charters`.

### Charter markdown mappings

When you open a charter markdown file (`charters/*.md` or `charters/**/README.md`),
charter-scoped mappings are available there too, including:

- `<localleader>A` archive current charter
- `<localleader>C` close current charter
- `<localleader>s` / `<localleader>S` open the charter pickers
- `<localleader>p` / `<localleader>P` workspace navigation

## Documentation

Full reference and tutorial in the built-in help:

```vim
:help clearhead
```

Covers setup, all keybindings, commands, LSP capabilities, the `.actions`
format, workspace layout, daily workflow, archiving lifecycle, and the Lua API.

## Development

The test suite uses upstream [Busted](https://lunarmodules.github.io/busted/)
inside Neovim through `nlua`; it does not depend on Plenary's retired test
adapter. Install the Lua 5.1 test dependencies and run the suite with:

```sh
luarocks --lua-version=5.1 install --local busted 2.3.0-1
luarocks --lua-version=5.1 install --local nlua 0.3.2-1
eval "$(luarocks --lua-version=5.1 path)"
busted tests
```

The living-loop integration test runs when both `clearhead` and
`clearhead-graphd` are on `PATH`; otherwise Busted reports it as pending. To
install the repository's pre-push gate:

```sh
git config core.hooksPath .githooks
```

## License

MIT
