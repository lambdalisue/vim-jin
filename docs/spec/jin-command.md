# :Jin

`:Jin [++option...] [{args}]` runs jj with `{args}` and shows what jj printed.

## What reaches jj

`{args}` reach jj as given. vim-jin adds nothing to them except settings that
keep the output plain (no color, no pager), and a flag in `{args}` such as
`--color=always` overrides those.

Arguments are split the way a POSIX shell splits them, so a command copied
from a terminal means the same in `:Jin`:

- White space separates arguments.
- Inside single quotes everything is taken literally.
- Inside double quotes everything is taken literally, except that a
  backslash escapes `"` and `\`.
- Outside quotes a backslash escapes the next character.

A bare `%`, written without quotes or a backslash, stands for the file of
the current buffer, relative to its workspace root; in a `:JinFile` buffer,
for the file it shows. The same holds for the arguments of `:JinBuffer` and
the view commands.

An unterminated quote is reported as an error and jj does not run. `|` is
not a command separator for `:Jin`, so a revset such as `root()|@` reaches
jj intact. Unlike a shell, `:Jin` expands no variables, globs or `~`.

The options that start with `++` and come before `{args}` belong to vim-jin.
An unknown option is reported as an error and jj does not run. A `++`
argument after the first jj argument is passed to jj like any other.

`++wait`
: Return only after jj has finished, so that commands can be sequenced.

## Completion

`:Jin` completes its arguments with what the installed jj itself offers for
them: subcommands, flags, revisions, bookmarks, paths and the rest, asked in
the workspace `:Jin` would run in. Candidates are written to fit where they
are completed: escaped outside quotes, and inside an open quote continued
and closed. While `++` options can still be given, a word starting with `+`
completes to them instead.

jj's answers are reused for a few seconds, and dropped when a `:Jin` command
finishes, so a change made outside vim-jin can take that long to show up in
completion.

## Where it runs

jj runs in the workspace of the current buffer, falling back to the
workspace of the current directory. A `:JinBuffer` buffer counts as being in
the workspace it shows. Outside any workspace it runs in the
current directory, so commands that need no workspace, such as
`jj git init`, work too.

## What it shows

Everything jj printed is echoed and kept in the message history, in the
error highlight when jj fails.

## When it finishes

`:Jin` returns at once and jj runs in the background, unless `++wait` is
given.

After jj finishes, successfully or not, the `User JinCommandPost` autocmd
fires.
