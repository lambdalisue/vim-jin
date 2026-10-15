{
  description = "Work with Jujutsu (jj) repositories from Neovim and Vim";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (
        pkgs:
        let
          # The core runs on LuaJIT (Neovim) and on PUC Lua (what Vim is
          # usually built with), so the tests run on both. Each interpreter
          # gets its own busted under its own name, as both ship `busted`.
          bustedOn =
            name: lua:
            pkgs.writeShellScriptBin "busted-${name}" ''
              exec ${lua.withPackages (ps: [ ps.busted ])}/bin/busted "$@"
            '';
        in
        {
          default = pkgs.mkShell {
            # Say why each package beyond these is here.
            packages = [
              pkgs.just
              # `nix fmt` needs flake.nix in the Git index, which jj does not
              # update for new files, so the recipes call nixfmt directly.
              pkgs.nixfmt
              pkgs.stylua
              pkgs.selene
              pkgs.lua-language-server
              (bustedOn "luajit" pkgs.luajit)
              (bustedOn "lua54" pkgs.lua5_4)
            ];
          };
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
