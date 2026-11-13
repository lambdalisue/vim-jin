# Tug the nearest bookmarks up to a change and leave a wrong move to undo

Status: Accepted

## Context

jj never moves a bookmark on its own: once new changes are made on top of
`main`, `main` stays where it was until it is moved. Moving it was the most
frequent thing done to a bookmark in a view, and setting one by name made
every move a prompt to type, which jj also refused when the move went
backwards or sideways.

## Decision

The key for a bookmark on a change tugs the local bookmarks nearest below the
change up to it, without asking. Only with no bookmark below to tug does it
ask for a name. A second key sets a bookmark named when asked, wherever it
is, backwards and sideways too. Neither asks for confirmation: jj tells what
moved, and undo takes it back.

## Alternatives considered

- Ask for a name, offering the nearest bookmark as the answer to accept. The
  most frequent move still takes a prompt to confirm.
- Move a bookmark from its line to the selected change. It takes a selection
  first, and is what the bookmark view already does.
- Ask before moving a bookmark backwards. The operation log already keeps
  every move, so a question only slows down the move that was meant.

## Consequences

- A tug only ever moves bookmarks forwards, onto descendants.
- Bookmarks that sit on the same nearest change move together.
- A move that was not meant is undone, not prevented.
