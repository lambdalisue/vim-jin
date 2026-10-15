# Run `nix develop` (or use direnv) first so every tool is on PATH.

set shell := ["bash", "-euo", "pipefail", "-c"]

# List the recipes.
default:
    @just --list

# Format every source.
fmt:
    stylua lua test
    nixfmt flake.nix

# Check formatting without changing files.
fmt-check:
    stylua --check lua test
    nixfmt --check flake.nix

# Lint, and check the type annotations. `vim` is declared for the type
# checker as a whole; selene keeps it out of the core.
lint:
    selene lua
    selene --config test/selene.toml test
    lua-language-server --check . --checklevel=Warning

# Run every test.
test: test-core

# Run the core tests on LuaJIT (Neovim) and on PUC Lua (Vim).
test-core:
    busted-luajit
    busted-lua54

# Everything CI runs.
ci: fmt-check lint test
