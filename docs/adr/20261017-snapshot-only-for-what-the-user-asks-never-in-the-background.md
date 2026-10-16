# Snapshot only for what the user asks, never in the background

Status: Accepted

## Context

Every jj command snapshots the working copy and records an operation unless
told not to. vim-jin also asks jj things on its own: views are read again
when the user enters one or comes back to the editor, and the statusline
components refresh while the user edits, often while an agent runs jj in
the same repository. A snapshot or an operation taken where the user does
not look lands in the operation log as if the user had done something, and
two of them racing an agent's command split the operation log into heads
that the next command merges.

## Decision

What keeps a view the user has open current runs as jj does, snapshotting
the working copy so that edits made without jj show: a command, a view read,
and a view read again on entering it or on coming back to the editor. What
runs where the user does not look, the statusline components, passes
`--ignore-working-copy` and loads the repository at an operation of its
own, never merging a split operation log, so that it neither snapshots nor
records an operation of any kind.

## Alternatives considered

- `--ignore-working-copy` alone, loading the repository at its head. With
  the operation log split, jj merges the heads first, recording an
  operation all the same.
- Snapshotting for the components as well. The operation log would fill
  with snapshots the user never made, and they would race an agent's
  commands.
- Never snapshotting, not even for views. A view would show the working copy
  as of the last jj command, not as the files are.

## Consequences

- A component can lag behind files changed without jj until something a
  view does snapshots them.
- While the operation log is split, the components show one of its heads,
  leaving out what the others did, until a command merges them.
- Background queries have to cope with a split operation log themselves.
