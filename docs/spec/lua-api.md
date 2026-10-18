# Lua API

`require("jin")` is how vim-jin's own features and other plugins work with
jj. It runs in Neovim and in Vim built with `+lua`, and loads nothing from
the editor until one of its functions is called.

## Where jj runs

Every function runs jj in a workspace found the way `:Jin` finds it: from
`opts.cwd` when given, or else from the current buffer and then the current
directory. Outside any workspace jj runs in that directory itself. A
relative `opts.cwd` or `path` is taken from the current directory.

## `jin.jj(argv, opts?, on_exit?)`

Runs `jj` with `argv` and returns what it printed, as
`{ code, stdout, stderr }`. Nothing is echoed and no event fires, so it is
safe for reading jj's output at any time. Output is plain text without a
pager; `opts.color = true` asks jj for ANSI colors instead.

With `on_exit`, it returns at once and calls `on_exit` with the result on
the main loop. Without, it blocks until jj finishes and returns the result.

`opts.env` adds environment variables for jj. `opts.stdin` is written to
jj's standard input, as `jj describe --stdin` reads it; without it jj reads
no input. `opts.on_stderr` is called with each line of jj's standard
error as soon as jj prints it, while the result still holds all of it.

## `jin.command(argv, opts?, on_exit?)`

Does what `:Jin` does with `argv`: runs jj, echoes what it printed, and then
fires `User JinCommandPost`. Use it for commands that change the
repository, so that everything showing the repository refreshes.

It returns at once unless `opts.wait` is true. `opts.stdin` is handed to jj
as for `jin.jj()`. So is `opts.on_stderr`. `opts.quiet` echoes nothing
unless jj fails, for a command whose result shows elsewhere. `opts.silent`
echoes nothing at all, failures included, for a caller that tells them
itself. `on_exit`, if given, receives the result after the echo. `argv` is
handed to jj as is: `++` options exist only on the `:Jin` command line, and
`opts` takes their place here.

## `jin.buffer(argv, opts?)`

Does what `:JinBuffer` does with `argv`, and returns the buffer number. The
`++` options of `:JinBuffer` are fields of `opts` here: `opener`,
`monochrome` and `filetype`. `opts.mods` takes modifiers such as
`botright`, `opts.reload = true` stands for the `!`, and `opts.cwd` picks
the workspace as for the other functions.

## `jin.view(name, argv, opts?)`

Does what the view command of `name` does with `argv` (`"log"` for
`:JinLog`, and so on; see `views.md`), and returns the buffer number.
`opts` is as for `jin.buffer()`, plus `opts.line`, the line to put the
cursor on once the view has been read.

## `jin.component(name)`

Returns the component `name` of the current buffer's workspace, as
`jin#component#get()` does; see `components.md`.

## `jin.root(path?)`

Returns the root of the workspace holding `path`, or of the current buffer
or directory when `path` is nil. Returns nil outside any workspace.
