{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.keyfinder;
in
{
  options.services.keyfinder = {
    enable = lib.mkEnableOption "Keyfinder, the ZSA keyboard layer overlay for macOS 26+";
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.keyfinder;
      defaultText = lib.literalExpression "keyfinder.packages.\${pkgs.stdenv.hostPlatform.system}.keyfinder";
      description = "Keyfinder app bundle to install and launch.";
    };
    startAtLogin = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Start Keyfinder in the primary user's graphical login session.
        Requires system.primaryUser. Leave the app's own launch-at-login
        toggle off when this option is enabled. Quit remains effective until
        the next login or service reload; the agent is not kept alive.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    launchd.user.agents.keyfinder = lib.mkIf cfg.startAtLogin {
      managedBy = "services.keyfinder.startAtLogin";
      serviceConfig = {
        Label = "io.keyfinder.app";
        ProgramArguments = [
          "${cfg.package}/Applications/Keyfinder.app/Contents/MacOS/Keyfinder"
          "--background"
        ];
        RunAtLoad = true;
        KeepAlive = false;
        LimitLoadToSessionType = "Aqua";
        ProcessType = "Interactive";
      };
    };
  };
}
