# Views

A view is a `:JinBuffer`-like buffer that also knows what its lines stand
for, so that actions on a line lead somewhere. Everything `jin-buffer.md`
says about `:JinBuffer` holds for views as well: they open at once and fill
in the background, take the same `++` options and `!`, run in the same
workspace, complete jj's arguments, and read jj again on
`User JinCommandPost`.

Views also follow what jj does outside the editor, in another terminal or
by an agent: entering a view, or the editor regaining focus, reads the views
of that workspace again when the repository moved on since, files changed
without jj included, unless every view of it passes `--ignore-working-copy`
or `--at-op`, with which jj takes no snapshot either.
A view at a given operation stays as it is; one relative to the latest, such
as `--at-op @-`, moves on with it.

Views read jj's own formats: the log through the user's configured
templates, diffs in jj's color-words format. vim-jin adds markers to the
templates to tell which change each line belongs to; they never show.

In the log, where a change takes several lines, all the lines of the
one under the cursor are highlighted, across the window, with
`JinCursorEntry`, which links to `CursorLine` unless defined otherwise.
Lines of the graph alone, such as `~` below the last change shown, are not
part of it.

## Commands

`:JinLog [args]`
: `jj log` with `[args]`, in the user's log template (`templates.log`, or a
  `-T` given in `[args]`). jj's own word wrapping is turned off so that the
  text and the changes stay aligned; set `'wrap'` to wrap.

`:JinShow [args]`
: `jj show` with `[args]`, in the user's show template, with the diff in
  color-words format.

`:JinDiff [args]`
: `jj diff` with `[args]`, in color-words format. Each file is folded
  (opened).

`:JinFile [args]`
: `jj file show` with `[args]`, highlighted with the filetype of the path
  shown.

`:JinFile` needs the path of a file in `[args]` (`%` names the current
one); without it it says so and opens nothing.

## Actions

Every view has these actions, mapped as `<Plug>(jin-action-{name})` in
normal and visual mode:

`choice`
: Ask for an action by name, with completion, and run it.

`repeat`
: Run the action last chosen with `choice` again.

`help`
: List the actions with the keys mapped to them, the window variants of
  an action on its line.

An action that opens a view comes in four variants: `{name}` opens it in
the current window, `{name}:split`, `{name}:vsplit` and `{name}:tab` in a
new one. A view opened from a change names the change by its change ID, so
that it follows the change through rewrites, or by its commit ID when the
change is divergent or the commit is hidden, as an older version of a change
is, since the change ID would lead to its latest version instead.

A view showing the repository at an earlier operation (`--at-op`) opens
further views at that operation too, and never takes today's working copy
for the files of that time.

A line that names nothing an action needs, such as a header, or one shared
by two changes when a template prints no newline, offers nothing to act on.
A key pressed there does nothing and says nothing; an action chosen by name
with `a` says why it cannot run.

### Log

`show`
: Show the change of the line.

`diff`
: Show the diff of the change of the line.

`yank:change`, `yank:commit`
: Yank the change IDs or commit IDs of the lines, one per line, into the
  register given.

### Show and diff

`jump`
: Open the file of the line at that line, on the side the line is on: the
  new side, or the old side for a removed line or file. When that side is the
  working copy, the file itself opens; any other revision opens
  `:JinFile`.

`jump:old`, `jump:new`
: Open the file on the old or the new side, whichever line the line has.
  The old side of a renamed file is its old path. A merge has no single old
  side, its parents merged together, so jumping there says so and opens
  nothing.

The show view also has `yank:change` and `yank:commit`. In a show view, the
sides are the version of the change shown on the line, by its commit ID (so
that an older version stays that version), and its
parents; the working-copy commit's new side is the working copy itself. In a
diff view they are those the arguments compare (`-r`/`--revisions`, or
`--from` and `--to`, by default the working copy and its parent).

The show view also has:

`parent`, `child`
: Show the parent or the child of the version on the line, or, when it has
  several, a log of them to choose from.

### File

`log`
: Show the log of the changes that touched the file, up to the revision
  shown.

## Default key mappings

Each view maps keys to its actions and motions unless
`g:jin_{view}_disable_default_mappings` is set, `{view}` being the name
in the first column below (`buffer` for `:JinBuffer`). A key the buffer
already maps itself, as an ftplugin of the user may, is left alone. The keys
follow rules rather than a list, and none of them changes what the key
means in Vim. A key either keeps its meaning while the view tells
what it applies to, as `yy` still yanks and `]]` still
goes to the next section, or it is a key that edits text, which a
read-only buffer has no use for, given the change closest to what it does
to text. Vim's motions and marks keep working, and `=` stays Vim's
operator. `a`, `.` and `?` are the deliberate exceptions. A view maps only
the keys of the actions it has.

- `a` chooses an action by name, `.` repeats it and `?` lists the actions.
- `<CR>` goes to what the line names, as it does in the quickfix window,
  serving what the view is opened for: showing the change of a log line,
  opening the file of a diff line.
- `<S-CR>` and `<C-CR>` serve what the view is opened for next most often,
  such as the diff of a log line or the log of the file of a file view.
  Both are mapped, as a terminal may pass on only one of them.
- `<C-w><CR>` opens what `<CR>` opens in a new window, split vertically
  when `'diffopt'` holds `vertical` and horizontally otherwise.
- `gd` goes to the diff, `gp` and `gc` to the parent and the child.
- `yy` yanks what the line stands for, and `y` in visual mode what the lines
  selected stand for.
- `YY` yanks the commit IDs of the changes, in a view that has them, and `Y`
  in visual mode those of the lines selected.
- `]]` and `[[` go to the first line of the next and the previous block,
  in a view that has blocks, as Vim's section motions go between
  sections: with a count, in visual and operator-pending mode too, and
  leaving where they came from in the jumplist. A count past the last
  block stops at it; with no block that way, the cursor stays. A block is
  an entry in the log view; a file in the diff view; the header of each
  change and each file in the show view. The other views have no blocks
  and leave `]]` and `[[` to Vim.
  The keys are mapped to `<Plug>(jin-next-block)` and
  `<Plug>(jin-prev-block)`, which are there for keys of the user's own
  even when the default mappings are disabled.

Keys that start others, as `g` and `CTRL-W` do, wait as long as
`'timeoutlen'` for the rest. The openers that have no key of their own, and
every variant, such as `{name}:tab`, are reached through `a` or by mapping
`<Plug>(jin-action-{name})`.

| View | `<CR>` | `<S-CR>` | `g` keys | `yy` | `YY` |
| --- | --- | --- | --- | --- | --- |
| log | show | diff | `gd` | yank:change | yank:commit |
| show | jump | | `gp` `gc` | yank:change | yank:commit |
| diff | jump | | | | |
| file | | log | | | |
