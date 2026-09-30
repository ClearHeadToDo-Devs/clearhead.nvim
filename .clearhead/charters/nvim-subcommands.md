---
id: 01a0dd04-2f75-77e7-8cf7-515083689aa3
alias: nvim-subcommands
state: Active
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
| `:ClearheadQuery [name]` | `:Clearhead query index [name]` | `query index [name]` |
| `:ClearheadTree [name]` | `:Clearhead query tree [name]` | `query tree [name]` |
| `:ClearheadGraph [name]` | `:Clearhead query graph [name]` | `query graph [name]` |
| (none) | `:Clearhead jot` | `jot`, not built yet |

The dispatcher lives in `lua/clearhead/command.lua`. One tree drives both dispatch and completion, and a leaf can supply its own `complete` function for arguments.

## Log

- 2026-09-29T22:12-07:00 — Dispatcher is lua/clearhead/command.lua: one verb-noun tree drives dispatch and completion; a new command is one table entry, and a leaf may supply complete(lead, rest).
- 2026-09-29T22:12-07:00 — Decisions: clean break from :ClearheadX (no wrappers); diff dropped; archive maps to 'archive charter' since archive_workspace already ran 'archive charter --closed'; 'open root' replaces the inbox naming.
- 2026-09-29T22:12-07:00 — 'clearhead query list' is the authority for view names (TYPE column: index/tree/graph, built-in and saved). It only prints a box table with no --format, so query.parse_list is fragile; a 'query list --format json' in clearhead-cli would fix it.
- 2026-09-29T22:12-07:00 — 'query index chain' exits 0 with no rows when given no target; the CLI models it as its own verb 'query chain <QUERY>'. command.lua filters it from index completion via needs_target until that verb is mirrored.
- 2026-09-29T22:12-07:00 — The quickfix refresh (view.lua) re-runs only the view name stored in the list context (clearhead_query), so any view taking arguments (chain target, --charter) must record its args there first or refresh will silently drop them.
- 2026-09-29T22:12-07:00 — Testing: 'busted tests' runs in about 0.1s; for live checks use 'timeout 20 nvim --headless -u NONE -l script.lua'. Heredoc-heavy one-liners and unbounded headless nvim runs hung the shell twice, so use script files and timeouts.
- 2026-09-29T22:47-07:00 — view-args done: qf context stores the argv after 'clearhead query' (string name = shorthand for {index, name}); refresh re-runs it from the CURRENT cwd by design (cwd = the user's declared workspace, same rule as query.lua), and the title shows the literal command + workspace so a post-:cd refresh explains itself. Full-suite 'hang' earlier was the heredoc shell issue again, not busted.
