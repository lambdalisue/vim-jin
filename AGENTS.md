# vim-jin

Work with Jujutsu (jj) repositories from Neovim and Vim.

## How it is built

- **Test first.** Red → green → refactor. Write the failing test before the
  code that makes it pass.
- **Each layer holds one thing.** Put a fact in the one layer that owns it,
  and nowhere else.

  | Layer | Holds |
  | --- | --- |
  | `docs/concept.md` | what this is and for whom |
  | `docs/adr/` | one decision and why it was made |
  | `docs/spec/` | the behaviour users and other components can rely on |
  | Tests | the details that pin the behaviour down: rules, boundaries, tables |
  | Code | how it is done |
  | Commits | why a change was made |
  | Comments | why it is not done another way |

  Before writing, fixing or reviewing a record, read `docs/adr/README.md`;
  before writing, fixing or reviewing a spec, read `docs/spec/README.md`.
  Follow their writing order.
- **The core talks to no editor.** Code under `lua/jin/`, outside
  `lua/jin/host/`, runs on plain Lua: no `vim` global, nothing that only
  LuaJIT provides. It is written for Lua 5.1 and must also run on newer PUC
  Lua. It reaches the editor through the host layer it is given
  (`docs/adr/20261015-reach-the-editor-only-through-a-host-layer.md`).
- **Features run jj through the public API.** A feature calls
  `require("jin").jj()` or `.command()`, the API other plugins use, never the
  internal modules behind it
  (`docs/adr/20261015-build-every-feature-on-the-public-lua-api.md`).
- **Dependencies are current.** Before adding or bumping one, look up its
  latest release in the registry. Do not copy a version from memory or from
  another repository.

## Quality gate

Run `just ci` inside the development shell before reporting a change as done.
CI runs the same recipe.

jj does not add new files to the Git index, and Nix only sees files in it. In
a checkout with untracked new files, enter the shell with
`nix develop path:.` instead of `nix develop`.

## Layout

| Path | What lives there |
| --- | --- |
| `lua/jin/` | the core, editor-independent Lua |
| `lua/jin/init.lua` | the public Lua API; binds the core to the running editor's host |
| `lua/jin/host/` | the host layer: one implementation per editor |
| `plugin/` | the Ex commands, shared by both editors |
| `test/` | busted tests for the core, run on LuaJIT and PUC Lua |
| `test/host/` | host tests, run inside Neovim and Vim by `test/host/run.lua` |
| `docs/` | concept, ADRs, specs, references |
| `doc/` | the Vim help: what the specs promise, retold for users; change it with them |

## Language

- README, docs and commit messages: English
- Code comments, log and error messages: English

## Commits

Scoped Commits:

```
<scope>: <description>

<why this change is needed>
```

- The scope names where the change is, from the table below. Several scopes
  are joined with `, `; a change across the whole tree uses `treewide`.
- The description starts in lower case, has no trailing period, and stays
  within 72 characters.
- The body explains why. The code shows how; the tests show what.
- A release commit is `release: vX.Y.Z`.
- A breaking change says so in the body and carries a `BREAKING CHANGE:`
  trailer.

| Scope | Covers |
| --- | --- |
| `core` | `lua/jin/` and its tests in `test/`, except the host layer |
| `host` | `lua/jin/host/`, `plugin/` and `test/host/` |
| `docs` | `docs/concept.md`, `doc/`, `README.md`, `AGENTS.md` |
| `adr` | `docs/adr/` |
| `spec` | `docs/spec/` |
| `tooling` | `justfile`, formatter, linter, type checker and test runner configs |
| `ci` | `.github/` |
| `nix` | `flake.nix`, `flake.lock` |
| `deps` | dependency updates |

Add a row when a new area appears.
