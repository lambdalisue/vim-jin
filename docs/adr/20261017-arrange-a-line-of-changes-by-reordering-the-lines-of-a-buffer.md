# Arrange a line of changes by reordering the lines of a buffer

Status: Accepted

## Context

jj arrange reorders changes in a terminal interface of its own, which an
editor cannot drive. Reordering is otherwise one rebase per change, each
naming where it goes, while what the user has in mind is simply the order
they want the changes in.

## Decision

A buffer lists a line of changes, one per buffer line, each named by its
change ID. Writing the buffer with its lines in another order rebases the
changes into that order, one change at a time, and the changes that sat on
the newest one stay on whatever is newest afterwards. Only a line is taken:
changes each with one parent, the one before, none with another change on
it outside the list but the newest. Only the order is read: lines are never
added or removed, and their text after the ID writes nothing.

## Alternatives considered

- Running jj arrange itself in a terminal inside the editor. It works on any
  graph, but its keys and screen are its own, and nothing of the editor
  applies.
- Moving changes one by one with the rebase actions and the selection. It
  already works, but takes a step and a selection for every change moved.
- Reordering any graph, branches included, from a buffer. A list of lines
  has no way to say where a branch goes.

## Consequences

- A write can stop partway, when jj refuses a rebase, and leave the changes
  partly reordered; restoring the operation before the write takes it all
  back.
- A divergent change cannot be arranged, as its change ID names more than
  one version.
- The shape of the line is known only to jj, so a selection that is not one
  is refused when written, not when listed.
