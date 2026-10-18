# Name buffers by full IDs and title them by the shortest prefixes

Status: Accepted

## Context

An action that opens a view of a change puts the change or commit ID into the
buffer name, and the title the statusline shows is made from that name. jj
prints these IDs in full, which makes the title long, while jj itself accepts
the shortest unique prefix and highlights it. How short a prefix can be is
known only to jj, and it grows as the repository does. A view is read again
from its name whenever the repository moves on.

## Decision

Buffer names keep change and commit IDs in full. The title shows each as the
shortest prefix jj gives for it, asked of jj each time the view is read.

The change and commit under the cursor keep a fixed length in the statusline,
with the shortest prefix highlighted as jj highlights it. The prefixes come
with what jj prints for the view, beside each entry's IDs.

## Alternatives considered

- Put the shortest prefixes into the buffer names. A prefix unique when the
  view opened can become ambiguous later, and the view, read again from its
  name, would then fail or show another revision.
- Cut every ID in the title to a fixed length. It is not the prefix jj shows
  elsewhere, and is longer than needed or, in a large repository, ambiguous.
- Show the change under the cursor by its shortest prefix alone, as the title
  does. The statusline would change its width as the cursor moves.
- Ask jj for the prefix of the change under the cursor. The statusline is
  drawn on every cursor move, and would run jj each time.

## Consequences

- Reading a view that names full IDs runs one more jj command, and the buffer
  is drawn once both have answered.
- An ID jj gives no shortest prefix for, such as an operation ID, is still cut
  to a fixed length.
