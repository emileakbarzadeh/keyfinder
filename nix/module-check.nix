{
  self,
  nix-darwin,
  system,
  pkgs,
}:
let
  evaluate =
    settings:
    (nix-darwin.lib.darwinSystem {
      inherit system;
      modules = [
        self.darwinModules.default
        {
          nix.enable = false;
          system.stateVersion = 6;
          system.primaryUser = "keyfinder-test";
          services.keyfinder = settings;
        }
      ];
    }).config;
  disabled = evaluate { };
  enabled = evaluate { enable = true; };
  manual = evaluate {
    enable = true;
    startAtLogin = false;
  };
  customPackage = pkgs.emptyDirectory;
  custom = evaluate {
    enable = true;
    package = customPackage;
  };
  service = enabled.launchd.user.agents.keyfinder.serviceConfig;
  package = self.packages.${system}.keyfinder;
in
assert !(disabled.launchd.user.agents ? keyfinder);
assert !(builtins.elem package disabled.environment.systemPackages);
assert builtins.elem package enabled.environment.systemPackages;
assert builtins.elem package manual.environment.systemPackages;
assert !(manual.launchd.user.agents ? keyfinder);
assert service.RunAtLoad && !service.KeepAlive;
assert service.Label == "io.keyfinder.app";
assert service.LimitLoadToSessionType == "Aqua";
assert
  service.ProgramArguments == [
    "${package}/Applications/Keyfinder.app/Contents/MacOS/Keyfinder"
    "--background"
  ];
assert
  custom.launchd.user.agents.keyfinder.serviceConfig.ProgramArguments == [
    "${customPackage}/Applications/Keyfinder.app/Contents/MacOS/Keyfinder"
    "--background"
  ];
assert builtins.elem customPackage custom.environment.systemPackages;
assert enabled.launchd.daemons == disabled.launchd.daemons;
assert builtins.all (assertion: assertion.assertion) enabled.assertions;
# This is an evaluation report; its printed paths are not build dependencies.
pkgs.writeText "keyfinder-module-check.json" (
  builtins.unsafeDiscardStringContext (
    builtins.toJSON {
      inherit system;
      checks = [
        "disabled"
        "installed"
        "manual-launch"
        "graphical-session"
        "quit-stays-quit"
        "custom-package"
        "no-root-daemon"
        "darwin-assertions"
      ];
      launchAgent = service;
    }
  )
)
