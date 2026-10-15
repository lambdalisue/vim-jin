# Mark entries inside the user's own templates

Status: Accepted

## Context

Views such as the log need to know which change each line of jj's output
stands for, so that actions on a line can act on that change. jj prints its
log, show, operation log and the like through templates the user can
configure, and the point of vim-jin is to show jj's output as the user has
set it up.

## Decision

vim-jin wraps the template jj would use (the configured `templates.*`
setting, or the user's `-T`) so that each entry starts with a marker: an
ASCII record separator, the IDs of the entry separated by spaces, and a unit
separator. It removes the markers before showing the output and maps every
line to the entry whose marker last started. jj's own word wrapping is
turned off where markers are used, since jj would count them as visible
text.

## Alternatives considered

- Run jj twice, once for display and once in a machine-readable template,
  and match the two by order. Graph lines and multi-line entries make the
  matching fragile, and the two runs can see different repository states.
- Parse IDs out of the displayed text. That ties vim-jin to the built-in
  templates and breaks on any template that does not print the IDs, or
  prints them shortened.
- Show only vim-jin's own templates. That gives up the user's configuration,
  which is what makes jj's output familiar.

## Consequences

- Any template works, as long as it ends each entry with a newline. A line
  that holds two markers, or no marker before it, maps to no entry, and
  actions on it do nothing.
- Every view that needs line metadata costs one extra jj call, to read the
  configured template, unless `-T` is given.
- `ui.log-word-wrap` has no effect in these views; the editor's own wrapping
  takes its place.
