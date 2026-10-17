# Support only the jj release the development shell pins

Status: Accepted

## Context

vim-jin reads what jj prints: its templates, its diff formats, its conflict
markers and the arguments its commands take. jj is still at 0.x, and these
change between releases, sometimes without a deprecation period. vim-jin
itself has not been released, and nobody depends on it yet working with any
other jj.

## Decision

Until vim-jin's first release, it supports the one jj release its
development shell provides: the one the nixpkgs revision in `flake.lock`
pins, which CI and the host tests run against. Updating that revision
updates jj, and is made together with whatever the new jj requires.

## Alternatives considered

- A minimum version, with CI running both it and the latest release. Each
  difference between the two would need a branch in the code and a test on
  both sides, for users who do not exist yet.
- Whatever jj release is newest, with CI on it unpinned. CI would break on
  an upstream release with no change in vim-jin, and nothing would record
  which release vim-jin last worked with.

## Consequences

- Users are told which jj release is supported, and that statement follows
  the pin.
- A user with another jj may find views that read wrongly.
- Updating `flake.lock` for any other tool updates jj as well, and has to be
  checked as a jj update.
