{ pkgs, appBundle }:
let
  # libisofs otherwise adds "????" Finder type/creator metadata to every file.
  # That metadata invalidates signed app bundles on modern macOS.
  imageWriter = pkgs.libisoburn.override {
    libisofs = pkgs.libisofs.overrideAttrs (previous: {
      patches = (previous.patches or [ ]) ++ [ ./patches/hfsplus-no-finder-info.patch ];
    });
  };
  imageConverter = pkgs.callPackage ./libdmg-hfsplus.nix { };
  layoutPython = pkgs.python3.withPackages (python: [
    python.ds-store
    python.mac-alias
    python.pillow
  ]);
  volumeName = "Keyfinder";
  volumeID = builtins.substring 0 16 (builtins.hashString "sha256" "${appBundle}");
in
pkgs.runCommand "keyfinder-${appBundle.version}-macos-${pkgs.stdenv.hostPlatform.system}.dmg"
  {
    nativeBuildInputs = [
      imageWriter
      imageConverter
      layoutPython
    ];
    env.TZ = "UTC";
  }
  ''
    mkdir contents
    cp -R ${appBundle}/Applications/Keyfinder.app contents/
    ln -s /Applications contents/Applications
    python3 -B ${../scripts/dmg-layout.py} contents ${volumeName}
    xorriso -as mkisofs -V ${volumeName} -r -hfsplus \
      -hfsplus-serial-no ${volumeID} -uid 0 -gid 0 \
      --modification-date=2001010100000000 \
      --set_all_file_dates 2001010100000000 \
      -o uncompressed.dmg contents
    # Finder opens a read-only UDIF image in a window when it mounts; it
    # does not do that for the raw image xorriso writes.
    dmg -c zlib -l 9 dmg uncompressed.dmg "$out" > /dev/null
  ''
