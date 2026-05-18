# clearhead.nvim

Neovim plugin for the [ClearHead](https://github.com/ClearHeadToDo-Devs/clearhead-cli)
action management framework. Provides filetype support, LSP integration, and
editor-native commands for working with `.actions` files.

## Requirements

- Neovim 0.10+
- `nvim-treesitter` with the `actions` grammar installed
- `clearhead` CLI (optional but recommended — provides LSP, formatting, archiving)
  ```bash
  cargo install clearhead
  ```

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "ClearHeadToDo-Devs/clearhead.nvim",
  ft = "actions",
  config = function()
    require("clearhead").setup({})
  end,
}
```

## Setup

```lua
require("clearhead").setup({
  -- all options are optional; these are the defaults
  default_file          = "inbox.actions",
  nvim_auto_normalize   = true,   -- assign missing UUIDs on save
  nvim_format_on_save   = true,   -- format via LSP on BufWritePre
  nvim_lsp_enable       = true,   -- auto-attach clearhead-lsp
  nvim_lsp_binary_path  = "",     -- explicit binary path (auto-detected)
  nvim_inbox_file       = "",     -- override inbox path
  nvim_default_mappings = true,   -- enable <localleader> keybindings
})
```

## Documentation

Full reference and tutorial in the built-in help:

```vim
:help clearhead
```

Covers setup, all keybindings, commands, LSP capabilities, the `.actions`
format, workspace layout, daily workflow, archiving lifecycle, and the Lua API.

## License

MIT
