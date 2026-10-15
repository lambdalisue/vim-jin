# Reach the editor only through a host layer

Status: Accepted

## Context

vim-jin targets Neovim first and aims to run on Vim built with `+lua`. The
two editors expose different Lua APIs: Neovim has `vim.api`, `vim.uv` and
`vim.system`; Vim has `vim.fn`, `vim.command`, `vim.list` and `vim.dict`, and
returns editor values as userdata rather than Lua tables. Code that calls
either API directly runs on that editor only.

## Decision

The core never touches the `vim` global. It reaches the editor through a host
layer, which has one implementation per editor and is chosen when vim-jin
loads. Values cross the layer as plain Lua tables and strings: the host layer
converts editor values on the way in and out.

## Alternatives considered

- Call Neovim's API directly and port to Vim later. Every module would need
  rewriting for the port, so Vim support would never be within reach.
- Write against the subset both editors share (`vim.fn` and Ex commands).
  That subset has no common way to run a process asynchronously, returns
  different value types on each editor, and would deny Neovim its own API
  even where only Neovim matters.
- Put the editor-facing code in Vim script, which both editors run. The logic
  would be split between two languages, and Vim script is slower than LuaJIT
  for the parsing vim-jin does.

## Consequences

- The core runs, and is tested, on plain Lua without an editor.
- Every new editor feature the core needs is first added to the host
  interface and implemented for both editors.
- Features only Neovim can offer live in the Neovim host implementation and
  are optional.
