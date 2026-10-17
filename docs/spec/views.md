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
as the one commit that wrote the line. A line of a selected change shows as
selected even then. Moving the cursor runs no jj.

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

`:JinArrange [args]`
: A line of changes, newest first, one per line, to reorder: the changes
  `-r` names in `[args]`, or the mutable ancestors of the working copy
  (`::@ & mutable()`), which make a line only while none of them is a
  merge. Only the order of the lines counts, read by the change ID that
  starts each; the rest of a line writes nothing. Written, the buffer
  rebases the changes into the order of its lines, the changes that sat on
  the newest staying on whatever is newest. Anything but a reordering of one
  line of changes is refused before anything is rebased, as a write is in a
  view at an earlier operation, and so is a write when the line is no longer
  the one the buffer was read with: reordered, or with a change added or
  gone, as by a split or a rebase elsewhere meanwhile, since writing its
  order would put back what was done to changes nobody moved in the buffer.
  A rebase jj refuses stops the write there:
  the changes moved so far stay moved, each move an operation of its own,
  and the buffer stays unwritten. Like a description buffer, it is read
  once and never again by itself; `:edit` reads it again.

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

### Selection

The log, show, evolog, annotate and operation show views select changes
as the other side of an action that takes two, such as the change
to squash into. The selection belongs to the workspace for the editing
session: every view of it shows the lines of a selected change with
`JinSelected`, which links to `Visual` unless defined otherwise, over the
highlight of the line under the cursor; it keeps showing them when read
again. The selection names a change as the views do, so it follows the
change through rewrites. It is vim-jin's own and leaves Vim's marks alone.

`select`
: Select the change of the line, or of every line selected, or leave it
  out of the selection when selected.

`select:clear`
: Clear the selection of the workspace.

### Changing the repository

The log, show, evolog, annotate and conflicts views also change the
repository, and the status view commits. Such an action never runs on a
view at an earlier operation. In the log, annotate and conflicts views, whose lines show the latest version of their changes, it does not
run on a change rewritten since the view was read, as by an agent
meanwhile: the view is read again instead, and says so.

`describe`
: Edit the description of the change of the line, or of every line
  selected, in a description buffer.

`new`
: Create a change on top of the change of the line, or a merge of the
  changes of every line selected and the selected ones, and make it the
  working copy.

`new:after`, `new:before`
: Insert a new change between the changes of the lines and their children,
  or their parents, and make it the working copy.

`edit`
: Make the change of the line the working copy.

`abandon`
: Abandon the changes of the lines, once confirmed.

`squash`
: Squash the changes of the lines into the selected change, or, with nothing
  selected, the change of the line into its parent. The result keeps the
  descriptions of both sides, joined by a blank line, as jj would offer
  them to edit; one selected change at most.

`rebase`
: Rebase the changes of the lines, with their descendants, onto the selected
  changes.

`rebase:revisions`, `rebase:branch`
: Rebase onto the selected changes only the changes of the lines, their
  descendants left in place, or the whole branch they are on.

`rebase:after`, `rebase:before`
: Move only the changes of the lines in between the selected changes and
  their children, or their parents.

`put:after`, `put:before`
: The other way round: move only the selected changes in between the
  change of the line and its children, or its parent.

`duplicate`
: Duplicate the changes of the lines.

`revert`
: Create a change reverting the changes of the lines, on top of the selected
  change, or of the working copy with nothing selected.

`absorb`
: Move the parts of the change of the line into the changes below it that
  last touched those lines.

`parallelize`
: Make the changes of the lines siblings.

`bookmark`
: Set a bookmark, named when asked, to the change of the line.

`next`, `prev`
: Move the working copy to the next or the previous change.

`next:edit`, `prev:edit`
: Make the next or the previous change itself the working copy.

The operation log has, besides:

`restore`
: Restore the repository to how it was after the operation of the line,
  once confirmed.

An action that takes the selected changes as its other side leaves them out
of the selection once jj succeeded, keeping them when it fails, and says so
when it needs a selected change and finds none.

`commit`
: Commit the working copy, whatever the line, with a description written
  in a description buffer; the status view has it too. `:w` hands it to
  `jj commit`, as long as the working copy is still the change the buffer
  was opened for and its description is still the one read, and says so
  otherwise. Once committed, the buffer closes: the window it was opened
  over shows again what it showed before, and a window or tab page opened
  for it closes. A commit that fails leaves the buffer as it is.

Every view, these included, also has:

`undo`, `redo`
: Undo the latest operation, or redo the one last undone, without asking,
  as `u` and `CTRL-R` do in Vim.

jj's report of a change shows only when it fails; the views read again show
the result.

A description buffer holds jj's own draft of the description, and that of
each of several changes under a head of its own, as jj's editor does. `:w`
describes each change with its text, leaving out what jj's editor would
leave out, and marks the buffer written once jj took every one; jj's report
is shown only when it fails. When a description changed since the buffer
was read, as an agent may change it, `:w` says so and describes nothing. A
version named by its commit ID, as the version of a divergent change is, is
replaced by the `:w` that describes it, so `:w` refuses it after that and
says to describe it again from a view. Leaving the buffer unwritten changes
nothing. It describes the changes it was opened for, and is never read again
by itself, so that what is being written is not lost.

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

`delete`
: Delete the local bookmarks of the lines, once confirmed. A remote
  bookmark goes once the deletion is pushed, so a line of one is passed
  over.

`forget`
: Forget the bookmarks of the lines, local and remote, without deleting
  them on any remote.

`track`, `untrack`
: Track or stop tracking the remote bookmarks of the lines.

`move`
: Move the local bookmark of the line to the selected change, wherever it
  is.

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

`update-stale`
: Update the working copy of the workspace of the line once another
  workspace rewrote it (`jj workspace update-stale`, run in that
  workspace).

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
already maps itself, as an ftplugin of the user may, is left alone. A
buffer that is edited, a description buffer or the arrange buffer, maps no
key, its actions reached only through `<Plug>(jin-action-{name})`. The
keys follow rules rather than a list, and none of them changes what the
key means in Vim. A key either keeps its meaning while the view tells
what it applies to, as `yy` still yanks, `u` still undoes and `]]` still
goes to the next section, or it is a key that edits text, which a
read-only buffer has no use for, given the change closest to what it does
to text. Vim's motions and marks keep working, and `=` stays Vim's
operator. `a`, `.` and `?` are the deliberate exceptions. A view maps only
the keys of the actions it has.

Not changing the repository:

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
- `x` selects the change of the line, or of the lines selected in visual
  mode, or leaves it out when selected, and `X` clears the selection of the
  workspace.
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

Changing the repository:

- `u` undoes the latest operation and `CTRL-R` redoes it, in every view.
- `dd` abandons the changes of the line, and `d` in visual mode those of
  the lines selected; in the bookmark view they delete the bookmarks.
- `o` inserts a new change below the change of the line, as the log lists
  it, between it and its parent (`new:before`), and `O` above it, between
  it and its children (`new:after`).
- `i` makes the change the working copy (`edit`).
- `cc` commits the working copy, and `cw` describes the change.
- `J` squashes the change, or in visual mode those of the lines selected,
  into the selected change, or into its parent.
- `p` and `P` move the selected changes in after or before the change of
  the line (`put:after`, `put:before`).
- `gb` sets a bookmark, named when asked, to the change.

Keys that start others, as `d`, `c`, `g` and `CTRL-W` do, wait as long as
`'timeoutlen'` for the rest. Every other action, such as `rebase`,
`duplicate`, `revert`, `absorb`, `parallelize`, `restore`, `next` and
`prev`, the bookmark view's `forget`, `track`, `untrack` and
`move`, the workspace view's `update-stale`, the openers that have no key
of their own, and every variant, such as `{name}:tab`, is reached through
`a` or by mapping `<Plug>(jin-action-{name})`.

| View | `<CR>` | `<S-CR>` | `g` keys | Changes | `yy` | `YY` |
| --- | --- | --- | --- | --- | --- | --- |
| log | show | diff | `gd` `gb` | `u` `<C-r>` `dd` `o` `O` `i` `cc` `cw` `J` `p` `P` | yank:change | yank:commit |
| show | jump | | `gp` `gc` `gb` | `u` `<C-r>` `dd` `o` `O` `i` `cc` `cw` `J` `p` `P` | yank:change | yank:commit |
| diff | jump | | | `u` `<C-r>` | | |
| interdiff | jump | | | `u` `<C-r>` | | |
| file | annotate | log | | `u` `<C-r>` | | |
| oplog | show | log | | `u` `<C-r>` | yank:operation | |
| opshow | show | diff | `gd` | `u` `<C-r>` | yank:change | yank:commit |
| evolog | interdiff | show | `gd` `gb` | `u` `<C-r>` `dd` `o` `O` `i` `cc` `cw` `J` `p` `P` | yank:change | yank:commit |
| status | inspect | open | `gf` `gd` | `u` `<C-r>` `cc` | yank:path | |
| annotate | show | | `gf` `gd` `gb` | `u` `<C-r>` `dd` `o` `O` `i` `cc` `cw` `J` `p` `P` | yank:change | yank:commit |
| bookmark | log | show | | `u` `<C-r>` `dd` | yank:bookmark | |
| workspace | tcd | log | | `u` `<C-r>` | | |
| conflicts | files | | `gd` `gb` | `u` `<C-r>` `dd` `o` `O` `i` `cc` `cw` `J` `p` `P` | yank:change | yank:commit |
| resolve | edit | | `gf` `gd` | `u` `<C-r>` | | |

`resolve` is the list of conflicted paths `files` opens.
