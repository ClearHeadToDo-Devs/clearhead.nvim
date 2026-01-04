# Overview
This is a Neovim plugin that is intended to implement the functionality that will support the [custom actions grammar](https://github.com/ClearHeadToDo-Devs/tree-sitter-actions).

Now, you are interesting because this is orthogonal to the [CLI](https://github.com/ClearHeadToDo-Devs/clearhead-cli) implementation that is intended to serve as the CLI and rust backend for clearhead.

## Functionality
- Configuring the action filetype and buffers for optimal editing experience
- **Automatic Formatting & Normalization**: Automatically adds missing UUIDs and formats actions on save (via LSP or CLI).
- **LSP Integration**: Diagnostics, code actions (Hydrate Action), and inlay hints.
- providing an interface to update and edit filtered action files and sync those back

## Configuration

ClearHead follows a standard [Configuration Specification](https://github.com/ClearHeadToDo-Devs/specifications/blob/main/configuration_specification.md) across all its tools. It uses JSON for global/project config and supports environment variable overrides.

### Precedence
1. **Built-in defaults**
2. **Global configuration**: `~/.config/clearhead/config.json`
3. **Project configuration**: `<project-root>/.clearhead/config.json`
4. **Environment variables**: `CLEARHEAD_*`
5. **Setup options**: Options passed to `require('clearhead').setup({})`

### Example `setup()` options

```lua
require('clearhead').setup({
  -- Core settings
  default_file = "inbox.actions",
  project_files = {"next.actions", ".actions"},
  
  -- Neovim specific settings
  nvim_auto_normalize = true,    -- Ensure UUIDs exist on save
  nvim_format_on_save = true,    -- Format spacing on save
  nvim_lsp_enable = true,        -- Automatically start clearhead-lsp
  nvim_lsp_binary_path = "/path/to/clearhead_cli", -- Optional explicit path
})
```

### Environment Variables

You can override any setting via environment variables:

- `CLEARHEAD_DATA_DIR`
- `CLEARHEAD_DEFAULT_FILE`
- `CLEARHEAD_NVIM_FORMAT_ON_SAVE`
- ...and more.

### Project Detection
ClearHead automatically detects projects by searching upward for a `.clearhead/` directory or any file listed in `project_files` (default: `next.actions`). When a project is detected, it will:
1. Load `<project-root>/.clearhead/config.json`
2. Use the project-local default file (e.g., `next.actions`) for `:ClearheadInbox` if no explicit `nvim_inbox_file` is set.

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
