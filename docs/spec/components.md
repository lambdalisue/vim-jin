# Components

Components are short strings about the workspace of the current buffer, for
`'statusline'`, `'tabline'` or `'winbar'`:

```vim
set statusline+=%{jin#component#get('change')}\ %{jin#component#get('state')}
```

From Lua, `require("jin").component(name)` returns the same.

| Name | Shows |
| --- | --- |
| `change` | the shortest unique prefix of the working-copy change ID |
| `description` | the first line of the working-copy change's description |
| `state` | `empty`, `conflict` and `divergent`, as they apply to the working-copy change |
| `bookmarks` | the nearest bookmarks at or below the working copy |
| `traffic` | for each of those tracked on a remote and not in step with it, `name@remote` with `↑n` (commits the local bookmark is ahead) and `↓n` (behind) |
| `workspace` | the workspaces whose working copy is this change, when the repository has several workspaces |

## Never in the way

Reading a component never runs jj and never fails: it returns what the last
refresh found, or `""` before the first refresh, outside any workspace, for
an unknown name, or when jj could not answer.

Refreshes run in the background, when a component is read and its value is
half a minute old, when a buffer is entered or the editor regains focus
(at most twice a second), and after every `:Jin` or `jin.command()` — the
last three only for a workspace whose components have been read, so jj never
runs for someone who does not show them. They
look at the repository with `--at-op=@ --ignore-working-copy`: they neither
snapshot the working copy nor add an operation to the operation log, so
watching never changes what an agent sees. As a consequence, an edit not yet
snapshotted by any jj command shows up after the next one.

When jj commands run at the same time, such as by several agents, the
operation log can diverge into several heads until a later jj command merges
them. Refreshes then read the head that ended last, still without merging
the heads or adding an operation, so components keep showing the newest
state rather than going blank.

A refresh that fails replaces what earlier ones found: the components read
`""` until a refresh succeeds again.

When a refresh changes any component, `User JinComponentPost` fires. Redraw
on it to keep the statusline current:

```vim
autocmd User JinComponentPost redrawstatus
```
