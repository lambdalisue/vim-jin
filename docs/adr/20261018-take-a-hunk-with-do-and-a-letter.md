# Take a hunk with do and a letter

Status: Accepted

## Context

The pane a diff editor or a merge tool leaves to edit is a buffer being
edited, in diff mode, where Vim already gets a hunk from the other buffer
with `do` and puts one there with `dp`. With three buffers in diff mode,
Vim's own `do` and `dp` do not know which buffer to use. gin.vim's panes
for conflicts meet the same case with `dol` and `dor`, `do` followed by
the side.

## Decision

In the pane to edit, a hunk is taken with `do` and a letter naming where
it comes from: the pane on the left, the one on the right, both in either
order, or the base of a conflict; `do` alone takes both. The panes around
it put a hunk into it with `dp`. These keep what `do` and `dp` mean in
Vim, and tell only which buffer.

## Alternatives considered

- A prefix and a letter of vim-jin's own, such as `=` and a letter. In a
  buffer being edited `=` filters, so its letters must avoid every text
  object, and the keys differ from those of Vim's diff mode for the same
  thing.
- Vim's `:diffget` with a buffer number. The number differs every time the
  panes open, and has to be looked up first.

## Consequences

- `do` waits, as long as `'timeoutlen'`, for a letter that may follow.
- `do` alone takes both sides: deleting what is not to stay is how part of
  a hunk goes into the result, as it is how a conflict keeps parts of both
  sides.
