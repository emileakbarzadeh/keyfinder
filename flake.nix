{
  description = "Keyfinder — a ZSA keyboard layer overlay for macOS 26+";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nix-darwin.url = "github:lnl7/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-darwin,
    }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate =
            package:
            builtins.elem (nixpkgs.lib.getName package) [
              "apple-command-line-tools"
              "zapp"
            ];
        };
      packagesFor = system: import ./nix/packages.nix { pkgs = pkgsFor system; };
    in
    {
      packages = forAllSystems (
        system:
        let
          packages = packagesFor system;
        in
        {
          inherit (packages) keyfinder dmg;
          default = packages.keyfinder;
        }
      );

      apps = forAllSystems (system: (packagesFor system).apps);
      devShells = forAllSystems (system: {
        default = (packagesFor system).devShell;
      });
      formatter = forAllSystems (system: (pkgsFor system).nixfmt-tree);

      darwinModules.default = self.darwinModules.keyfinder;
      darwinModules.keyfinder = import ./nix/module.nix { inherit self; };

      overlays.default = final: prev: {
        keyfinder = self.packages.${final.stdenv.hostPlatform.system}.keyfinder;
      };

      checks = forAllSystems (system: {
        package = self.packages.${system}.keyfinder;
        module = import ./nix/module-check.nix {
          inherit self nix-darwin system;
          pkgs = pkgsFor system;
        };
      });
    };
}
