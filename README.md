# Overview
This is a Neovim plugin that is intended to implement the functionality that will support the [custom actions grammar](https://github.com/ClearHeadToDo-Devs/tree-sitter-actions).

Now, you are interesting because this is orthogonal to the [CLI](https://github.com/ClearHeadToDo-Devs/clearhead-cli) implementation that is intended to serve as the CLI and rust backend for clearhead.

## Functionality
- Configuring the action filetype and buffers for optimal editing experience
- **Automatic Formatting & Normalization**: Automatically adds missing UUIDs and formats actions on save (via LSP or CLI).
- **LSP Integration**: Diagnostics, code actions (Hydrate Action), and inlay hints.
- providing an interface to update and edit filtered action files and sync those back

## LSP Capabilities

The `clearhead-lsp` server (bundled in `clearhead`) provides the following to any editor that speaks LSP:

| Capability | What it does |
|---|---|
| **Completion** (`@`, `%`, `^`) | Date snippets: now, today, tomorrow |
| **Code Actions** | Hydrate UUID, set completion date, set/derive creation date |
| **Semantic Tokens** | Highlighting for id, priority, state, name, description, story, context, dates |
| **Inlay Hints** | Due-date countdown ("due in 3d", "due today") and completion age ("done 5d ago") |
| **Go to Definition** | Jump to first occurrence of a story or context tag |
| **Find References** | List all occurrences of a story or context tag |
| **Document Formatting** | Normalizes the file: adds missing UUIDs, fixes spacing, reindents |
| **Diagnostics** | Linting warnings (missing UUID, invalid dates) on every change |
| **Execute Command** | `clearhead/archive` — archives completed action trees via `workspace/applyEdit` |
| **Telemetry** (on save) | Diffs saved state to emit action lifecycle events |

### What stays in the plugin

These operations run locally for responsiveness — no LSP roundtrip:

- **State cycling** — tree-sitter finds and replaces the state character directly
- **Smart new action** — inserts a line with correct depth and creation date; UUID added by format-on-save
- **Status line** — counts completed/total via tree-sitter query
- **Completion date stamp** — appends `%<timestamp>` when state is set to completed

## Configuration

ClearHead follows a standard [Configuration Specification](https://github.com/ClearHeadToDo-Devs/specifications/blob/main/configuration_specification.md) across all its tools. It uses JSON for global config and supports environment variable overrides.

### Precedence
1. **Built-in defaults**
2. **Global configuration**: `~/.config/clearhead/config.json`
3. **Environment variables**: `CLEARHEAD_*`
4. **Setup options**: Options passed to `require('clearhead').setup({})`

### Example `setup()` options

```lua
require('clearhead').setup({
  -- Core settings
  default_file = "inbox.actions",

  -- Neovim specific settings
  nvim_auto_normalize = true,    -- Ensure UUIDs exist on save
  nvim_format_on_save = true,    -- Format spacing on save
  nvim_lsp_enable = true,        -- Automatically start clearhead-lsp
  nvim_lsp_binary_path = "/path/to/clearhead", -- Optional explicit path
  nvim_default_mappings = true,  -- Set to false to disable default mappings
})
```

### Default Mappings

When `nvim_default_mappings` is enabled (default: `true`), the following buffer-local mappings are available in `.actions` files using your `<localleader>` (default: `\`):

| Mapping | Action |
|---------|--------|
| `<localleader><space>` | Cycle action state |
| `<localleader>f` | Format/Normalize current file |
| `<localleader>i` | Open Inbox |
| `<localleader>p` | Browse workspace (opens data directory) |
| `<localleader>a` | Archive completed action trees |
| `<localleader>o` | New smart action below |
| `<localleader>x` | Set state to **Completed** (`x`) |
| `<localleader>-` | Set state to **In Progress** (`-`) |
| `<localleader>=` | Set state to **Blocked** (`=`) |
| `<localleader>_` | Set state to **Cancelled** (`_`) |

### Statusline Integration

You can display the current buffer's action progress (e.g., `✓ 5/12`) in your statusline:

```lua
-- Example for lualine.nvim
require('lualine').setup({
  sections = {
    lualine_x = { 
      { function() return require('clearhead').get_status() end } 
    }
  }
})
```

### Environment Variables

You can override any setting via environment variables:

- `CLEARHEAD_DATA_DIR`
- `CLEARHEAD_DEFAULT_FILE`
- `CLEARHEAD_NVIM_FORMAT_ON_SAVE`
- ...and more.

### Usage with conform.nvim

If you use `conform.nvim` for formatting, you can integrate `clearhead` easily:

```lua
local clearhead = require('clearhead')

require('conform').setup({
  formatters_by_ft = clearhead.get_conform_opts().formatters_by_ft,
  formatters = clearhead.get_conform_opts().formatters,
})
```

### Manual Usage
- `:ClearheadInbox`: Open your configured inbox file.
- `:ClearheadWorkspace`: Browse your workspace directory (works great with oil.nvim, snacks.nvim, etc.).

## Development Philosophy

`clearhead.nvim` is designed as a **Thin Client**. 

1. **LSP-First**: Business logic (like archiving, linting, or complex formatting) should live in the Rust CLI/LSP, not in Lua. 
2. **Commands over Shell**: Prefer calling LSP commands (`workspace/executeCommand`) instead of spawning shell jobs with `jobstart`. This allows the LSP to return `WorkspaceEdit` objects, providing a smoother experience without buffer reloads.
3. **AST in Rust**: While Tree-sitter is available in Neovim, complex AST manipulations are preferred in the Rust LSP to ensure portability to other editors (VSCode, Zed, etc.).

## Requirements
- Neovim 0.11+
- tree-sitter support enabled
  - and the `tree-sitter-actions` grammar installed
- (optional) the cli installed for syncing functionality
