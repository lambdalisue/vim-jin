# vim-jin

Work with Jujutsu (jj) repositories from Neovim and Vim.

vim-jin is the [jj](https://github.com/jj-vcs/jj) counterpart of
[vim-gin](https://github.com/lambdalisue/vim-gin): it runs jj, shows what jj
prints in buffers, and lets you act on them. It targets Neovim first and aims
to run on Vim built with `+lua` as well.

**Early development. Anything may change without notice.**

## Install

Install it with any plugin manager. It needs jj on `PATH`, and either Neovim
0.10 or later, or Vim 9.0.0067 or later built with `+lua`.

## Development

Enter the development shell with `nix develop` (or copy `.envrc.sample` to
`.envrc` and `direnv allow`), then:

```sh
just fmt   # format every source
just ci    # everything CI runs: format check, lint, type check, tests
```

The design lives in [docs/concept.md](docs/concept.md), the decisions behind it
in [docs/adr/](docs/adr/), and the behaviour it promises in
[docs/spec/](docs/spec/).

## License

MIT. See [LICENSE](LICENSE).
