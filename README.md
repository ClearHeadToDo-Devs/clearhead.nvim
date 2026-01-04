# Overview
This is a Neovim plugin that is intended to implement the functionality that will support the [custom actions grammar](https://github.com/ClearHeadToDo-Devs/tree-sitter-actions).

Now, you are interesting because this is orthogonal to the [CLI](https://github.com/ClearHeadToDo-Devs/clearhead-cli) implementation that is intended to serve as the CLI and rust backend for clearhead.

## Functionality
- Configuring the action filetype and buffers for optimal editing experience
- **Automatic Formatting & Normalization**: Automatically adds missing UUIDs and formats actions on save (via LSP or CLI).
- **LSP Integration**: Diagnostics, code actions (Hydrate Action), and inlay hints.
- providing an interface to update and edit filtered action files and sync those back

## Configuration

```lua
require('clearhead').setup({
  auto_normalize = true,    -- Ensure UUIDs exist on save
  format_on_save = true,    -- Format spacing on save
  lsp = {
    enable = true,          -- Automatically start clearhead-lsp
  }
})
```

### Usage with conform.nvim

If you use `conform.nvim` for formatting, you can integrate `clearhead_cli` easily:

```lua
local clearhead = require('clearhead')

require('conform').setup({
  formatters_by_ft = clearhead.get_conform_opts().formatters_by_ft,
  formatters = clearhead.get_conform_opts().formatters,
})
```

### Manual Usage
- `:ClearheadInbox`: Open your configured inbox file.
- `:ClearheadOpenDir`: Open the first `.actions` file in the current directory.

### Requirements
- Neovim 0.11+
- tree-sitter support enabled
  - and the `tree-sitter-actions` grammar installed
- (optional) the cli installed for syncing functionality
