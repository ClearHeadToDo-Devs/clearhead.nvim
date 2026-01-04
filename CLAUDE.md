# Overview
This will be an interesting one. 


As always, review the [README](README.md) for more context on the overall project.

## Our Focus
We are intending to make the act of working with action files in Neovim as seamless as possible. This means optimzing the editing experience to make it as clean as possible and easy for people to install and use

While we will often reference the other projects, sharing as much as makes sense, however, we also want to be disciplined about keeping the Neovim plugin focused on the Neovim experience.

## Tools
Because we are drafting a Neovim plugin, I will be wanting to make sure you have the neovim MCP installed and set up. this way you can test your creations yourself!

This is critical because working with neovim plugins is an act of respecting precedent and making sure we do as much research as possible on good plugin design.

Done right, we can make functionality that is completely unmatched by other editors.
Done wrong, and it will feel like you are fighting the editor to do even the smallest things.

Small actions can have big impacts, this is the mantra of (Neo)vim and we are going to respect that.

### Dependencies
For some context we leverage some key dependencies in our structure
- `lazy.nvim` - for plugin management (`:h lazy.*`)
- `nvim-treesitter` for tree-sitter support (`:TSInstall actions` to install the grammar)
- `nfnl` - for writing the plugin in Fennel (`:h nfnl` for more info)

The full setup we will be using is documented at [my dotfiles](https://github.com/ca-mantis-shrimp/dotfiles)

## Development
I want to minimize the amount of web fetches you are working with so you may assume that both the CLI and parser are sibling repos to this one.

In addition, the dotifiles can be assumed to be installed and to be the setup that you are working with. Upon request i will even add them to the repo so you can simply explore them when necessary

### Testing
To run the configuration unit tests (standalone):
```bash
export LUA_PATH="./lua/?.lua;./lua/?/init.lua;;"
nvim -l tests/test_config.lua
```

To run the full integration suite (requires plenary.nvim):
```bash
nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```
