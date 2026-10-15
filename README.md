# vim-jin

Work with Jujutsu (jj) repositories from Neovim and Vim.

vim-jin is the [jj](https://github.com/jj-vcs/jj) counterpart of
[vim-gin](https://github.com/lambdalisue/vim-gin): it runs jj, shows what jj
prints in buffers, and lets you act on them. It targets Neovim first and aims
to run on Vim built with `+lua` as well.

**Early development. Anything may change without notice.**

```vim
:Jin new
:Jin ++wait describe -m "feat: add parser"
:Jin log -r 'root() | @'
```

## Install

Install it with any plugin manager. It needs jj on `PATH`, and either Neovim
0.10 or later, or Vim 9.0.0067 or later built with `+lua`. `:help jin`
covers everything below.

## Usage

`:Jin {args}` runs `jj {args}` in the workspace of the current buffer and
echoes what jj printed. See [docs/spec/jin-command.md](docs/spec/jin-command.md).

`:JinBuffer {args}` shows what `jj {args}` prints in a buffer instead, in
jj's own colors, and keeps it current as `:Jin` changes the repository:

```vim
:JinBuffer log
:JinBuffer ++opener=vsplit show @-
```

See [docs/spec/jin-buffer.md](docs/spec/jin-buffer.md).

vim-jin buffers are named after the workspace they show, which makes for a
long name; `b:jin_title` holds a short one, such as `jj log -r @-`:

```vim
set statusline=%{get(b:,'jin_title',expand('%'))}
```

The same is available from Lua, for your own mappings and plugins:

```lua
local jin = require("jin")

-- What :Jin does: run, echo, then fire User JinCommandPost.
jin.command({ "describe", "-m", "feat: add parser" })

-- Read jj's output without side effects.
local result = jin.jj({ "log", "--no-graph", "-r", "@", "-T", "change_id" })
print(result.stdout)

-- What :JinBuffer does.
jin.buffer({ "log" }, { opener = "vsplit" })
```

See [docs/spec/lua-api.md](docs/spec/lua-api.md).

## Development

Enter the development shell with `nix develop` (or copy `.envrc.sample` to
`.envrc` and `direnv allow`), then:

```sh
just fmt   # format every source
just ci    # everything CI runs: format check, lint, type check, tests
```

The design lives in [docs/concept.md](docs/concept.md), the decisions behind it
in [docs/adr/](docs/adr/), and the behaviour it promises in
[docs/spec/](docs/spec/).

## License

MIT. See [LICENSE](LICENSE).
