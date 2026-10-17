# Keep the selection per workspace as the other side of an action

Status: Accepted

## Context

Many jj operations take two sides: `squash --into` a change, `rebase` onto
one, `new` on top of several. An action runs on the lines under the cursor or
selected, which gives one side; the other is usually elsewhere in the graph,
often far from the first, and sometimes better found in another view, such
as an older log or the versions of a change in its evolog. A change found in
the log may also be where a bookmark listed in another view should move.

## Decision

Changes can be selected from the lines that list them, and the selection
names each change, by change ID so that it follows the change through
rewrites, or by commit ID when the change is divergent. The selection
belongs to a workspace for the editor session, not to a buffer: every view
of the workspace that lists changes shows it, and every action in it can
use it. An action that takes two sides takes the lines it runs on as one
side and the selected changes as the other; an action such as `new` takes
them as more of the same.

## Alternatives considered

- A selection per buffer. The other side is often found in another view,
  and a view read again would have to carry its selection over.
- The editor's own marks or registers. They name lines or text, not
  changes, so they break as soon as a view is read again, and they share
  their letters with what the user keeps there.
- Asking for the other side each time, by revset or by picking a line
  afterwards. It breaks the flow of acting on what is in sight, and a
  revset has to be typed.

## Consequences

- Every view that lists changes has to show which of them are selected,
  read again or not.
- A change selected by commit ID stops being named once the change is
  rewritten, as any selected change does once it is abandoned; jj says so
  when the selection is used.
- The selection is lost when the editor exits.
- It is not called marks, so that Vim's marks keep their name and keep
  working in a view.
