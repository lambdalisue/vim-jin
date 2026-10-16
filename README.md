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

Views go further: their lines lead somewhere. `:JinLog` shows the change
graph in your own log template, and `<CR>` on a change shows it; in
`:JinShow` and `:JinDiff`, `<CR>` on a line opens the file at that line, as
it is in the working copy or, for any other revision, through `:JinFile`.

```vim
:JinLog -r 'trunk()..@'
:JinDiff --from main
:JinFile -r @- %
```

To follow what was done to the repository, by you or by an agent,
`:JinOpLog` lists every operation (and opens the log as it stood after
one), `:JinEvolog` the versions a change went through (and the interdiff
between them), and `:JinStatus`, `:JinAnnotate`, `:JinBookmark`,
`:JinWorkspace` and `:JinConflicts` the rest. Views keep up with jj run
elsewhere, too: entering one, or coming back to the editor, reads it again
when the repository moved on.

The keys of every view follow the same few rules, and none of them changes what
the key means in Vim: a key keeps its meaning, as `yy` still yanks and `]]`
still goes to the next section, or it is a key that edits text, which a
read-only buffer has no use for, given the jj operation closest to what it does
to text. Vim's motions and marks keep working. `a`, `.` and `?` are the
exceptions:

| Key | Does |
| --- | --- |
| `<CR>` | what the view is opened for: show a change, jump to a file, annotate a file, ... |
| `<S-CR>` / `<C-CR>` | what it is opened for next most often |
| `<C-w><CR>` | what `<CR>` opens, in a new window split the way `'diffopt'` splits diffs |
| `gf` / `gd` / `gp` / `gc` | go to the file / the diff / the parent / the child |
| `yy` / `YY` | yank change IDs (or what the line stands for) / commit IDs |
| `]]` / `[[` | go to the next / previous block: change, file, or lines one change wrote |
| `a`, `.`, `?` | choose an action by name (every one without a key), repeat it, list them all |

Your own mappings of `<Plug>(jin-action-{name})` win over these. See
[docs/spec/views.md](docs/spec/views.md).

Statusline components keep the working copy in sight without ever adding an
operation:

```vim
set statusline+=%{jin#component#get('change')}\ %{jin#component#get('state')}
autocmd User JinComponentPost redrawstatus
```

See [docs/spec/components.md](docs/spec/components.md).

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
