# Choose one of several relatives in a view that remembers where it leads

Status: Accepted

## Context

From a file or an annotation, `parent` and `child` open the file as it is
in the parent or the child. A merge has several parents, and a change can
have several children, so there the user has to choose one. A log of them
was opened to choose from, but a line of the log leads to the change, not
to the file: choosing dropped the user out of the walk through the file's
history, and the file had to be found again by hand.

A log line does what the log view says, and the keys of a view are mapped
once, from the view alone, so a log cannot lead somewhere else for one
buffer without every action of the log asking which buffer it is in.

## Decision

Choosing one of several relatives on the way to a file happens in a view of
its own, the pick view. It lists the relatives as the log does, and its
buffer name carries what the choice is for: which view to open, the path,
and the line the cursor was on. Choosing a line goes on to that view of the
file in that change, on that line, as the single relative would have.

The show view keeps opening the log of the relatives: there the choice
leads to the change, which is what a line of the log already does.

## Alternatives considered

- A log whose lines lead to the file when its buffer name says so. Every
  action and key of the log would then depend on the buffer, and the log
  would no longer mean one thing.
- Asking for the relative in a prompt or a menu of the editor. It shows
  less of each change than the log does, and is unlike every other choice
  vim-jin offers, which is made on the lines of a view.
- A pick view for the show view too. Its choice would do exactly what the
  log's does, so it would add a view without adding a way.

## Consequences

- What the pick view leads to survives reading it again, and opening it
  again from the same line finds the same buffer.
- A pick view can lead only where its buffer name can say; leading to a new
  kind of view from it needs that view named there.
