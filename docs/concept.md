# Concept

This document describes what vim-jin is for and the ideas every design
decision rests on. It is rewritten in place as the concept evolves; decisions
built on it are recorded as ADRs.

## What it is

vim-jin is a plugin, written in Lua, for working with a
[Jujutsu](https://github.com/jj-vcs/jj) (jj) repository without leaving the
editor. It targets Neovim first, and aims to run on Vim built with `+lua` as
well.

It is the jj counterpart of [vim-gin](https://github.com/lambdalisue/vim-gin).
It does not put a new model on top of jj. It runs jj, shows what jj prints in
buffers, and lets the user act on those buffers and reload them.

## Who it is for

- People who already drive jj from the command line and want the same
  commands inside their editor, not a second UI to learn.
- vim-gin users moving their repositories to jj, who expect the same feel:
  raw commands, actions on buffers, and buffers that stay current.

## Principles

### jj's output is the interface

- `:Jin {args}` passes `{args}` to jj unchanged and echoes the result.
  `:JinBuffer {args}` does the same but shows the result in a buffer.
- Dedicated commands (`:JinLog`, `:JinStatus`, ...) accept jj's own flags and
  forward them to jj. vim-jin does not invent a parallel flag set.
- Colors come from jj itself (`--color=always`, converted to highlights).
  vim-jin does not re-highlight jj's output with its own syntax.
- vim-jin reads back only what an action needs, such as a change ID or a
  path. It finds that information in a way that still works with the user's
  own templates and revsets. It never forces a fixed format on what the user
  sees.

### A buffer is a pure function of its name

- Every vim-jin buffer has a URL-like name, for example
  `jinlog://{workspace};{flags}#{revset}`, and its content can be rebuilt from
  that name alone. `:edit` reloads it, and sessions and `:split` work without
  plugin-side state.
- The workspace root is recorded in the name. A command run from a vim-jin
  buffer therefore targets the same repository, wherever the current
  directory is.
- On a file-like vim-jin buffer, `%` resolves to the real file path, so the
  user can move between views of the same file (`:JinLog %`, `:JinDiff %`).

### Do it the Vim way

- Buffers are disposable by default (`nofile`, `bufhidden=unload`,
  `nomodifiable`). A buffer is writable only when writing it means something.
- When an operation edits text, the user does it by editing a buffer and
  writing it. A change description is edited as a buffer, and `:w` applies
  it.
- Where jj asks an external tool to edit a diff (`jj split`, `jj squash -i`,
  `jj diffedit`) or to resolve a conflict (`jj resolve`), the editor's diff
  mode is that tool. Hunks move with `dp` / `do`, and writing accepts the
  result.
- Opening options behave like `:edit`: `++opener`, `++enc`, `++ff`, and `!`
  to force.

### Actions first, mappings second

- Every operation on a vim-jin buffer is an action,
  `<Plug>(jin-action-{name})`. `a` picks one with completion, `.` repeats the
  last one picked, and `?` lists what the current buffer offers.
- Action names grow by `:` (`diff:vsplit`). Short names are aliases of
  longer ones.
- An action is written once and reused across buffers. Each buffer supplies
  only how to turn the selected lines into candidates.
- Default mappings are few and can be disabled. The action name, not the key,
  is the stable interface.

### Stay current without being asked

- `:Jin` runs asynchronously; `++wait` makes it synchronous for sequencing.
- After a command, a debounced `User JinCommandPost` fires, and open vim-jin
  buffers reload themselves.
- Statusline components never fail and always return a string. They update
  in the background, cache their result, and fire `User JinComponentPost`
  only when the value changes.
- Background queries stay out of the user's way. They do not snapshot the
  working copy and do not add operations to the operation log.

### Neovim first, Vim within reach

- The core does not call editor APIs directly. It talks to the editor through
  a thin host layer, with one implementation for Neovim and one for Vim.
  Editor values are converted at that layer, so the core only ever sees plain
  Lua tables and strings.
- The core is written for Lua 5.1 so that it runs on LuaJIT, and it stays
  within what newer Lua versions also accept, because Vim is usually built
  against them. LuaJIT-only libraries (`ffi`, `bit`, `jit`) are used only
  inside the Neovim host layer, and only with a fallback.
- The core is tested on plain Lua without an editor. Each host layer is
  tested inside its own editor.
- Features are designed around what both editors share: buffers, split
  windows, diff mode, and mappings. A feature that only Neovim can offer,
  such as integration with `vim.ui.select`, is an optional extra on Neovim,
  never a requirement of the design.

### Small, and allowed to break

- Options starting with `++` belong to vim-jin. Everything else goes to jj.
- Every command is configured the same way: default arguments, persistent
  arguments, and a switch for the default mappings.
- Features that do not earn their keep are removed. Until 1.0, backward
  incompatible changes are made without deprecation periods.

## What it does not do

- It does not translate jj into git vocabulary or emulate a git index. There
  is no "stage" in vim-jin.
- It does not run git. Git operations in a colocated repository go through
  `jj git` or a git plugin such as vim-gin.
- It does not reimplement jj's interactive interfaces (the built-in diff
  editor, the merge editor). It plugs the editor into jj's tool hooks instead.
- It does not support Vim without `+lua`. There is no Vim script
  implementation.
- It does not keep a static list of every action in its documentation. The
  `?` action shows the list at run time.
