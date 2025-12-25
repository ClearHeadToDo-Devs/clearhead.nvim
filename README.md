# Overview
This is a Neovim plugin that is intended to implement the functionality that will support the [custom actions grammar](https://github.com/ClearHeadToDo-Devs/tree-sitter-actions).

Now, you are interesting because this is orthogonal to the [CLI](https://github.com/ClearHeadToDo-Devs/clearhead-cli) implementation that is intended to serve as the CLI and rust backend for clearhead.

## Functionality
We are shooting for:
- Configuring the action filetype and buffers for optimal editing experience
- providing an interface to update and edit filtered action files and sync those back
- a set of helper functions and keymaps (if desired) to make working with action files easier
  - for example, instead of writing a UUID by hand, we will provide a hyrdration function to generate them on the fly
  - as well as completion support for various fields

### Requirements
- Neovim 0.11+
- tree-sitter support enabled
  - and the `tree-sitter-actions` grammar installed
- (optional) the cli installed for syncing functionality
