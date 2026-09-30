{ pkgs, appBundle }:
let
  # libisofs otherwise adds "????" Finder type/creator metadata to every file.
  # That metadata invalidates signed app bundles on modern macOS.
  imageWriter = pkgs.libisoburn.override {
    libisofs = pkgs.libisofs.overrideAttrs (previous: {
      patches = (previous.patches or [ ]) ++ [ ./patches/hfsplus-no-finder-info.patch ];
    });
  };
  volumeID = builtins.substring 0 16 (builtins.hashString "sha256" "${appBundle}");
in
pkgs.runCommand "keyfinder-${appBundle.version}-macos-${pkgs.stdenv.hostPlatform.system}.dmg"
  {
    nativeBuildInputs = [ imageWriter ];
    env.TZ = "UTC";
  }
  ''
    mkdir contents
    cp -R ${appBundle}/Applications/Keyfinder.app contents/
    ln -s /Applications contents/Applications
    xorriso -as mkisofs -V Keyfinder -r -hfsplus \
      -hfsplus-serial-no ${volumeID} -uid 0 -gid 0 \
      --modification-date=2001010100000000 \
      --set_all_file_dates 2001010100000000 \
      -o "$out" contents
  ''
