# :JinBuffer

`:JinBuffer[!] [++option...] [{args}]` opens a buffer showing what
`jj {args}` prints.

## What it shows

The buffer holds jj's output in jj's own colors, shown as highlights; the
escape codes themselves never reach the text. When jj fails, what it
reported on stderr is shown in the buffer as well.

jj runs in the background: the buffer opens at once and fills when jj
finishes, and the editor stays usable meanwhile. When a buffer is read again
before an earlier read finished, only the latest read is shown. A buffer
that was left and is read again on coming back to it, as with `CTRL-O`, puts
the cursor back where it was.

The buffer is read-only and not tied to a file, from the moment it opens,
so that plugins working on files, such as language clients, leave it alone,
even when its filetype is that of a file shown in it. Its filetype is
`jin-buffer` unless `++filetype` says otherwise.

The buffer name holds the workspace and is long; `b:jin_title` holds a
short title for a statusline or a tabline instead: the jj command shown,
such as `jj log -r @-`, with long IDs cut short.

## What reaches jj

`{args}` are split and handed to jj exactly as `:Jin` does
(see `jin-command.md`), and jj runs in the same workspace `:Jin` would use.
Completion offers the same candidates as for `:Jin`, and the `++` options of
`:JinBuffer`.

`++opener={opener}`
: Open the buffer with `{opener}` (`split`, `vsplit`, `tabedit`, ...)
  instead of `:edit`. Modifiers such as `:botright` or `:tab` given to
  `:JinBuffer` apply as well.

`++monochrome`
: Ask jj for plain output, without colors.

`++filetype={filetype}`
: Set the buffer's filetype.

## Staying current

The buffer's name records the workspace, the options and `{args}`, so the
buffer can always be rebuilt from its name: `:edit` reads jj again, and a
session or another window showing the buffer finds the same content.

Every loaded `:JinBuffer` buffer reads jj again when `User JinCommandPost`
fires, that is after any `:Jin` or `jin.command()`. Windows showing it keep
their cursor.

Opening a buffer that is already open switches to it as it is; with `!` it
reads jj again first.
