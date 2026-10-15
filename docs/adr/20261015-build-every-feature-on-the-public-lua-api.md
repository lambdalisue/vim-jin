# Build every feature on the public Lua API

Status: Accepted

## Context

Every feature vim-jin will add (buffers, actions, statusline components)
runs jj, and so would plugins written by others that want to work with jj
repositories. Each of them needs the same things `:Jin` already does: find
the workspace, run jj without a pager, and let everything showing the
repository know when it changed.

## Decision

vim-jin's own features run jj only through the public Lua API,
`require("jin")`, the same API offered to other plugins. Its `command()` is
the Lua counterpart of `:Jin` and fires `User JinCommandPost`; its `jj()`
returns what jj printed without side effects. `:Jin` itself is a thin parser
of the typed line on top of `command()`.

## Alternatives considered

- Let features call the internal modules and expose a separate API for
  others. The two would drift apart, and the public one would be the less
  exercised.
- Expose only the Ex command, as vim-gin did. Plugins would have to build a
  command line, quote it, and parse the echoed output back.

## Consequences

- The public API is exercised by every feature, so what other plugins rely
  on is what vim-jin itself relies on.
- Changing the public API is a breaking change for vim-jin's own features
  first, which keeps it small and deliberate.
