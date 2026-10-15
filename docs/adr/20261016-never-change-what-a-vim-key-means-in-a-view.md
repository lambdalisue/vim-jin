# Never change what a Vim key means in a view

Status: Accepted

## Context

A view is a buffer, and the user's fingers treat it as one: they move with
`w`, `b` and `e`, search with `/`, yank with `y`. The actions of a view need
keys, and a key the user knows that stops meaning what it means in a view
works everywhere but there.

The actions that change the repository need keys too. A read-only buffer
has no use for the keys that edit text, and most of them already name
something close to a jj operation: `u` undoes, `dd` deletes, `o` opens a
line below, `p` puts what was taken.

## Decision

A key a view maps keeps what it means in Vim. A view takes keys whose
meaning it keeps while telling what they apply to, as `yy` yanks what the
line stands for, `]]` goes to the next block of the view and `u` undoes the
latest operation, and keys that edit text, which a read-only buffer has no
use for. Each key that edits text is given the jj operation closest to what
it does to text: `dd` abandons, `o` and `O` make a change below and above,
`i` edits a change, `cc` commits, `cw` describes, `J` squashes, `p` and `P`
put the selected changes after and before the one under the cursor. An
operation no such key comes close to has no key, and no prefix is taken to
make room for it; `=` stays Vim's operator.

`a`, `.` and `?` are deliberate exceptions. They choose an action by name,
repeat it and list the actions, as they have in the author's plugins since
gita, and users of those plugins reach for them.

## Alternatives considered

- Doubled letters of the view's own, such as `ll` and `ee`. They take keys
  that move the cursor: `b` and `e` wait to see whether a second letter
  follows instead of moving at once.
- Map no key that moves the cursor. It leaves the views without the section
  motions users already type, and it says nothing of keys such as `?` that
  change their meaning without moving anything.
- Let a view take any key that is useful there. A view is a buffer like
  any other to the user's fingers, and every key taken would be one more
  thing that works everywhere but here.
- `=` and a letter of one meaning for every change. It is a second set of
  keys to learn beside the Vim ones that already come close, and `=` would
  not filter, which a user may still try in a view.
- `c` and a letter. `c` is the change operator, typed all the time while
  editing, and its letters would read as editing the text rather than
  changing the repository.
- `<LocalLeader>` and a letter. Users set it to keys of very different
  reach, and many keep it for mappings of their own.
- `s` and a letter. Motion plugins commonly take `s`, and the views would
  shadow them.

## Consequences

- `]]` and `[[` move between the blocks of a view: what a block is, the
  view decides.
- A new key is checked against what Vim gives it, not against whether it
  moves the cursor.
- A key may do different things a view apart, as `dd` abandons a change in
  the log and deletes a bookmark in the bookmark view, each the deletion of
  what the view lists.
- An operation without a close Vim key is reached only by name or by a
  mapping of the user's.
- `u` and `CTRL-R` act without asking, as they do in Vim; jj's operation
  log keeps what they undo.
- `?` does not search backward in a view, and `.` repeats an action rather
  than a change; this is the cost of the exceptions.
