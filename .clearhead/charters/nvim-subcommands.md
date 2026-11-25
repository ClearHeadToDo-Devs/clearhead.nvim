---
id: 01a0dd04-2f75-77e7-8cf7-515083689aa3
alias: nvim-subcommands
state: Closed
---
# Nvim Subcommands

The plugin exposes about a dozen separate commands (`:ClearheadInbox`, `:ClearheadQuickAdd`, `:ClearheadPickActions`, `:ClearheadArchiveWorkspace`, and others), each named differently. Replace them with one `:Clearhead` command that takes subcommands and offers tab completion.

## Decision (2026-09-26)

The command grammar mirrors the CLI: verb then noun, e.g. `:Clearhead add action`, `:Clearhead query index unscheduled`. Verb-noun also fits vim's own operator-then-motion shape. Where a command matches a CLI verb, the plugin uses the CLI's words and argument structure, and the CLI's grammar is the source of truth. Editor-only features (tree, graph, pickers, workspace root) get verbs of their own without being forced into CLI terms.

This also removes the "inbox" naming left over from root-next-default: `:ClearheadInbox` and quick add become ordinary verbs targeting the root `next.actions`.

## Resolved (2026-09-29)

- **Clean break.** The old `:ClearheadX` commands are gone, with no deprecated wrappers.
- **`query` mirrors the CLI** (`query index|tree|graph [name]`), so consistency with the CLI is the rule for every shared verb.
- **Editor-only verbs are `open` and `pick`.** `diff` was dropped because it only wrapped `:vert diffsplit %`.

| Old | New | CLI mirror |
|---|---|---|
| `:ClearheadQuickAdd` | `:Clearhead add action` | `add action` |
| `:ClearheadInbox` | `:Clearhead open root` | editor-only |
| `:ClearheadProjectRoot` | `:Clearhead open project` | editor-only |
| `:ClearheadWorkspace` | `:Clearhead open workspace` | editor-only |
| `:ClearheadPickActions` | `:Clearhead pick actions` | editor-only |
| `:ClearheadPickCharters` | `:Clearhead pick charters` | editor-only |
| `:ClearheadArchiveWorkspace` | `:Clearhead archive charter` | `archive charter --closed` |
| `:ClearheadQuery [name]` | `:Clearhead query index [name] [--charter C]` | `query index [name] --charter C` |
| `:ClearheadTree [name]` | `:Clearhead query tree [name]` | `query tree [name]` |
| `:ClearheadGraph [name]` | `:Clearhead query graph [name]` | `query graph [name]` |
| (none) | `:Clearhead query chain [target]` | `query chain <query>`; target defaults to the action under the cursor |
| (none) | `:Clearhead query show <name>` | `query show <name>` |
| (none) | `:Clearhead jot [--charter C] <text>` | `jot <text> --charter C`; charter defaults from the buffer |
| (none) | `:Clearhead debug` | `debug` |

The dispatcher lives in `lua/clearhead/command.lua`. One tree drives both dispatch and completion, and a leaf can supply its own `complete` function for arguments.
