# Hand jj's tools to the running editor as three panes, answered by writing the list

Status: Accepted

## Context

Some jj commands run an external tool and wait for it: a diff editor to
choose what part of a change stays, a merge tool to resolve a conflict. jj
runs as a background process of the editor, without a terminal, so it
cannot start another editor in front of the user, and the user's
configured tool would not be the editor they are working in. jj hands the
tool its own standard error, which reaches whoever reads jj's while jj
still waits.

A merge tool is handed the sides of a conflict and an output to write. A
diff editor is handed two sides and, when asked, an output to fill as well,
so both can show what is being made beside what it is made from. Whether
to go on is then answered from inside the editor, where every key already
means something in a buffer.

## Decision

For the commands vim-jin itself runs that need such a tool, vim-jin passes
jj a tool of its own: a helper that tells the running editor what to edit
by a line on jj's standard error and waits for an answer on a named pipe.
The user's own configuration of tools is never changed.

Both tools show a file as three panes: what jj takes, to edit, between
the two sides it comes from, read-only, each pane naming itself. The list
of the files answers jj as a buffer is written: writing it hands jj the
result, and leaving it in any other way, or the editor exiting, leaves
everything as it was.

## Alternatives considered

- Two panes, the right side edited in place. The change as it is goes out
  of sight as soon as it is edited, and the diff editor and the merge tool
  look and work differently.
- Answer with keys of the list, such as `ZZ` and `ZQ`. They mean writing
  and quitting a buffer, which the list then does not do, and a user has to
  learn them for this one buffer.
- Remote calls into the editor, such as `$NVIM` or Vim's client-server.
  Neovim and Vim offer different ones, Vim's needs a build with it, and the
  helper would have to find the right editor instance.
- Polling for files the helper and the editor leave each other. A
  half-written file can be read as an answer, and the helper has to keep
  looking for one instead of waiting.
- Leaving these commands to a terminal. The changes are then edited outside
  the editor that shows them, which is what vim-jin is for.

## Consequences

- The host has to deliver jj's standard error while jj runs, not only once
  it has finished.
- Every such command waits until the editor answers, so leaving the list
  without writing it has to answer abort, as the editor exiting does.
- Leaving the list once a file is edited is refused as for any buffer
  holding an edit, so that nothing edited is thrown away unasked.
- A command typed at `:Jin` keeps the user's own tool.
- The helper needs a POSIX shell and named pipes, which leaves Windows out
  until it gets a counterpart.
