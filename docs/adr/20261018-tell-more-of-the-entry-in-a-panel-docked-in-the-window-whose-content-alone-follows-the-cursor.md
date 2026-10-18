# Tell more of the entry in a panel docked in the window whose content alone follows the cursor

Status: Accepted

## Context

A view tells of each entry what its lines hold: the annotation in front of a
line of a file gives an ID, an author and a time in the few dozen columns
the user's template gives it, and a line of the log gives the first line of
a description. Why a line is as it is, or what an operation did, lives
elsewhere, and reading it meant leaving the view for another. What the view
is read for must stay in sight beside whatever tells more, and reading
beside it must not mean watching it come and go as the cursor moves.

## Decision

What a view has to tell of the entry under the cursor shows in a panel
docked at an edge of the view's window, at a size that does not change
from line to line. It stays open while the view is shown in the current
window, and only its content follows the cursor. Each window keeps whether
it shows the panel, as the user last left it there. The panel never hides
a line for good: room made of virtual lines or columns lets every line be
scrolled out from under it, and the cursor is kept out from under it.

## Alternatives considered

- A window floating over the annotation alone, never over the text. It
  opens, moves and changes its size as the cursor moves, where it can lie
  depends on the annotation's columns and on the rows wrapped lines go on
  in, and a view without an annotation has nowhere to put it.
- Float it beside the cursor, as language clients show a hover. It covers
  the very text the cursor is on.
- Echo it in the command line. It holds one line, so a description is cut
  as the statusline already cuts it.
- A preview window. It is opened and closed apart from the view, and moves
  the window the user is reading whenever it does.
- At the right, a real split beside the view, so that lines wrap before
  the panel. It resizes the windows around it whenever the panel is shown
  or hidden, and becomes a window that the user's window commands, `:only`
  and the cursor can reach. Neither editor has an option that wraps a
  window's lines before a column of it.
- Ask jj for all there is to tell of every entry along with the view. Every
  line would carry it, however few of the entries are ever looked at.
- One shown or hidden state for the whole session. Hiding the panel in one
  window would hide it in a window where it was being read.
- Keep the cursor out from under the panel with a window-local
  'scrolloff'. It keeps as many lines above the cursor as below, counts no
  virtual line, and Neovim scrolls no virtual line after the last line into
  view for it.

## Consequences

- A view tells only what goes in the panel; showing it, its size and its
  place are the same for every view.
- The content shows at once from what the entry itself holds, and jj is
  asked for the rest only once the cursor stays on an entry, once per entry
  for each read.
- The panel takes rows or columns of the window for as long as it is
  shown: at the bottom or the top, as many virtual lines go after the last
  line or before the first; at the right, a window that does not wrap gets
  as many virtual columns after every line, and in a window that wraps,
  the text under the panel stays hidden.
- vim-jin scrolls the view when the cursor moves under the panel, and moves
  the cursor when the view is scrolled over it.
- The host layer draws floating windows (floats in Neovim, popups in Vim),
  virtual lines and inline virtual text.
