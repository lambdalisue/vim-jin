# Check in the diff editor list how much of each file goes to the result

Status: Accepted

## Context

The diff editor list showed only whether a file was edited, which did not
tell whether the edit took all, part or none of its change, and so not what
`:w` would hand jj. Leaving a file out took `dol`, a key borrowed from the
panes, and taking it back meant opening the file.

## Decision

Each file of the list is boxed as jj's built-in diff editor boxes it: checked
when the result takes all of its change, partly when it takes some, empty when
it takes none. `x` toggles the box, leaving out a file wholly taken and taking
the others wholly, as it toggles the selection in the other views.

## Alternatives considered

- Two sections, taken and left out, as Git's staged and unstaged. A file
  partly taken belongs to both, and toggling one moves it away from the
  cursor.
- `dol` and `dor`, as in the panes. They take a side, not a box to mark, and
  toggling with one key needs no thought of which side is which.

## Consequences

- What `:w` hands jj can be read off the list without opening a file.
- `dol` no longer has a meaning in the list; taking a side whole stays
  reachable by name.
- A conflict to resolve has no sides to take, and so no box.
