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

In the log, the evolog, the operation log and the conflicts, where a
change, a version or an operation takes several lines, all the lines of the
one under the cursor are highlighted, across the window, with
`JinCursorEntry`, which links to `CursorLine` unless defined otherwise.
Lines of the graph alone, such as `~` below the last change shown, are not
part of it. In the status, the bookmarks, the workspaces and the conflicted
paths, where each line stands for one thing, the line under the cursor is
highlighted the same way.

In the annotation, every line written by the change of the line under the
cursor is highlighted, across the window, with `JinCursorChange`, which
links to `CursorLine` unless defined otherwise; a divergent change counts
as the one commit that wrote the line. Moving the cursor runs no jj.

In the annotation, a line too long for the window wraps after the
annotation: while a window shows the view, its `'breakindent'` is on and
the shift of its `'breakindentopt'` is as wide as the annotation, the other
items of that option kept, and once the window shows another buffer it has
that buffer's again. `'showbreak'` shows after the shift, or before it with
`sbr`. A `min` set in `'breakindentopt'` still holds, so that in a window
too narrow for it the shift is cut and a wrapped line goes on below the
annotation; without one, the view sets it to 1, in place of the editor's
20, so that a wrapped line goes on beside the annotation however narrow
the window.

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
  (opened). When no file changed, a gray note beside the empty buffer says
  so.

`:JinFile [args]`
: `jj file show` with `[args]`, highlighted with the filetype of the path
  shown.

`:JinOpLog [args]`
: `jj op log` with `[args]`, in the user's operation log template.

`:JinEvolog [args]`
: `jj evolog` with `[args]`: the versions a change went through, newest
  first, in the user's evolog template.

`:JinStatus [args]`
: `jj status` with `[args]`: the changes of the working copy and the paths
  left in conflict.

`:JinAnnotate [args]`
: `jj file annotate` with `[args]`, in the user's annotate template. The
  buffer holds the file itself, highlighted with the filetype of its path,
  and before each line shows, apart from its text, what the template prints
  before the line's content, in jj's colors. Searching and yanking see the
  file alone. When the template does not end each line with its content, or
  jj fails, jj's output shows whole instead.

`:JinBookmark [args]`
: `jj bookmark list` with `[args]`, in the user's bookmark list template.

`:JinWorkspace [args]`
: `jj workspace list` with `[args]`, in the user's workspace list template.

`:JinConflicts [args]`
: The log of the changes that hold conflicts (`jj log -r 'conflicts()'`),
  narrowed further by `[args]`.

`:JinFile` and `:JinAnnotate` need the path of a file in `[args]` (`%`
names the current one); without it they say so and open nothing.

`:JinCd`, `:JinLcd`, `:JinTcd` are not views: they change the current
directory (globally, for the window, or for the tab page) to the root of the
current buffer's workspace.

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

A view showing the repository at an earlier operation (`--at-op`, as the
operation log's `log` opens) opens further views at that operation too, and
never takes today's working copy for the files of that time.

A line that names nothing an action needs, such as a header, or one shared
by two changes when a template prints no newline, offers nothing to act on.
A key pressed there does nothing and says nothing; an action chosen by name
with `a` says why it cannot run.

A bookmark or workspace is acted on by its name as it is, even when the name
holds spaces or quotes and jj shows it quoted.

### Log

`show`
: Show the change of the line.

`diff`
: Show the diff of the change of the line.

`evolog`
: Show the versions the change of the line went through.

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
  nothing. Nor has an interdiff: its old side is the earlier version as jj
  rebases it to compare, which no revision holds.

The show view also has `yank:change` and `yank:commit`. In a show view, the
sides are the version of the change shown on the line, by its commit ID (so
that an older version, as the evolog opens, stays that version), and its
parents; the working-copy commit's new side is the working copy itself. In a
diff view they are those the arguments compare (`-r`/`--revisions`, or
`--from` and `--to`, by default the working copy and its parent).

The show view also has:

`parent`, `child`
: Show the parent or the child of the version on the line, or, when it has
  several, a log of them to choose from.

### File

`annotate`
: Show the file as it is in the revision shown with which change wrote each
  line of it, on the same line.

`log`
: Show the log of the changes that touched the file, up to the revision
  shown.

### Operation log

`show`
: Show what the operation changed (`jj op show`).

`log`
: Show the log as it was right after the operation (`jj log --at-op`).
  Reading it again keeps showing that moment.

`yank:operation`
: Yank the operation IDs of the lines.

### Operation show

What `show` opens from the operation log. Each line listing a change the
operation added or removed stands for that version of the change:

`show`, `diff`
: Show the version on the line, or its diff, by its commit ID, as a version
  the operation rewrote away is reached no other way.

`yank:change`, `yank:commit` as in the log.

### Evolog

`show`
: Show the version of the change on the line, by its commit ID.

`interdiff`
: Show how the diff of the version on the line differs from that of the
  version before it (`jj interdiff`), in a view that folds and jumps as
  the diff view does, the later version being the new side. When neither
  the files nor the description differ, a gray note says so.

`yank:change`, `yank:commit` as in the log.

### Status

`inspect`
: Show the diff of the path of the line, or the change of the working copy
  or of a parent on their lines. On any other line it does nothing, and
  says nothing.

`open`
: Open the file of the line, as `edit` does, or show the change of the
  working copy or of a parent on their lines. On any other line it does
  nothing, and says nothing.

`edit`
: Open the file of the line, as it is in the working copy, a conflicted
  one with the cursor on its first conflict.

`diff`
: Show the diff of the path of the line.

`annotate`
: Show which change wrote each line of the path.

`yank:path`
: Yank the paths of the lines.

### Annotate

`show`, `diff`
: Show the change that wrote the line, or its diff.

`log`
: Show the log up to the change that wrote the line.

`yank:change`, `yank:commit` as in the log.

`file`
: Show the file without the annotation, on the same line.

`log:file`
: The file view's `log`.


### Bookmark

`log`
: Show the log up to the bookmark of the line, local or remote.

`show`
: Show the change the bookmark points to.

`yank:bookmark`
: Yank the bookmark names, a remote one as `name@remote`.

A bookmark is named exactly, even when its name holds characters jj would
take for a pattern. A bookmark that points to no change, such as a remote
one not pushed yet, says so instead of showing anything.

### Workspace

`cd`, `lcd`, `tcd`
: Change the current directory to the root of the workspace of the line,
  and say which workspace, as the key pressed names neither the scope nor
  the place.

`log`, `show`
: Show the log up to the workspace's working copy, or that change.

### Conflicts

The actions of the log, and:

`files`
: List the conflicted paths of the change (`jj resolve --list`). On a
  path of that list, `edit` opens the file with its conflict, as
  `:JinFile` of the change, or the file itself when the change is the
  working copy, with the cursor on its first conflict; `diff` shows the
  diff of the path in the change.


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
  opening the file of a diff line, annotating the file of a file view, the
  interdiff of an evolog line, the diff of a status line.
- `<S-CR>` and `<C-CR>` serve what the view is opened for next most often,
  such as the diff of a log line or the log of the file of a file view.
  Both are mapped, as a terminal may pass on only one of them.
- `<C-w><CR>` opens what `<CR>` opens in a new window, where it opens a
  view or a file, split vertically
  when `'diffopt'` holds `vertical` and horizontally otherwise.
- `gf` goes to the file (as `:JinFile`, or the file itself as `edit` opens
  it), `gd` to the diff (the interdiff in the evolog), `gp` and `gc` to the
  parent and the child.
- `yy` yanks what the line stands for, and `y` in visual mode what the lines
  selected stand for.
- `YY` yanks the commit IDs of the changes, in a view that has them, and `Y`
  in visual mode those of the lines selected.
- `]]` and `[[` go to the first line of the next and the previous block,
  in a view that has blocks, as Vim's section motions go between
  sections: with a count, in visual and operator-pending mode too, and
  leaving where they came from in the jumplist. A count past the last
  block stops at it; with no block that way, the cursor stays. A block is
  a run of lines one change wrote in the annotate view; an entry in the
  log, conflicts, evolog and oplog views; a file in the diff and
  interdiff views; the header of each change and each file in the show
  view. The other views have no blocks and leave `]]` and `[[` to Vim.
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
| interdiff | jump | | | | |
| file | annotate | log | | | |
| oplog | show | log | | yank:operation | |
| opshow | show | diff | `gd` | yank:change | yank:commit |
| evolog | interdiff | show | `gd` | yank:change | yank:commit |
| status | inspect | open | `gf` `gd` | yank:path | |
| annotate | show | | `gf` `gd` | yank:change | yank:commit |
| bookmark | log | show | | yank:bookmark | |
| workspace | tcd | log | | | |
| conflicts | files | | `gd` | yank:change | yank:commit |
| resolve | edit | | `gf` `gd` | | |

`resolve` is the list of conflicted paths `files` opens.
