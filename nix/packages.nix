{ pkgs }:
let
  inherit (pkgs) lib;
  toolchain = pkgs.callPackage ./toolchain.nix { };
  # Nixpkgs' processed SDK removes SwiftShims for its own Swift package.
  # Apple's compiler needs those headers, so use the same pinned SDK source.
  sdk = pkgs.apple-sdk_26.src;
  sdkPath = "${sdk}";
  targetTriple = "${pkgs.stdenv.hostPlatform.darwinArch}-apple-macosx26.0";
  source = lib.fileset.toSource {
    root = ./..;
    fileset = lib.fileset.unions [
      ../Package.swift
      ../Sources
      ../Tests
      ../Packaging
    ];
  };
  appBundle = pkgs.stdenvNoCC.mkDerivation {
    pname = "keyfinder-app";
    version = "1.0.0";
    src = source;
    nativeBuildInputs = [
      toolchain
      pkgs.rcodesign
    ];
    buildInputs = [ sdk ];
    strictDeps = true;
    env = {
      SDKROOT = sdkPath;
      DEVELOPER_DIR = "${toolchain}";
      SWIFT_EXEC = "${toolchain}/usr/bin/swiftc";
      MACOSX_DEPLOYMENT_TARGET = "26.0";
      ZERO_AR_DATE = "1";
    };
    dontConfigure = true;
    buildPhase = ''
      runHook preBuild
      export CLANG_MODULE_CACHE_PATH="$TMPDIR/clang-module-cache"
      swift build --configuration release --disable-sandbox \
        --scratch-path .build --cache-path "$TMPDIR/swift-cache" \
        --config-path "$TMPDIR/swift-config" --security-path "$TMPDIR/swift-security" \
        --sdk "$SDKROOT" --toolchain "${toolchain}/usr" \
        --triple ${targetTriple} \
        -Xbuild-tools-swiftc -target -Xbuild-tools-swiftc ${targetTriple} \
        -Xbuild-tools-swiftc -module-cache-path -Xbuild-tools-swiftc "$TMPDIR/manifest-module-cache" \
        --jobs "$NIX_BUILD_CORES" \
        -Xswiftc -gnone \
        -Xswiftc -debug-prefix-map -Xswiftc "$PWD=/keyfinder" \
        -Xlinker -reproducible
      runHook postBuild
    '';
    doCheck = true;
    checkPhase = ''
      runHook preCheck
      .build/release/KeyfinderCoreChecks
      runHook postCheck
    '';
    installPhase = ''
      runHook preInstall
      app="$out/Applications/Keyfinder.app"
      install -Dm755 .build/release/Keyfinder "$app/Contents/MacOS/Keyfinder"
      ${toolchain}/usr/bin/strip -S "$app/Contents/MacOS/Keyfinder"
      install -Dm644 Packaging/Info.plist "$app/Contents/Info.plist"
      install -Dm644 Packaging/Keyfinder.icns "$app/Contents/Resources/Keyfinder.icns"
      cp -R .build/release/Keyfinder_KeyfinderCore.bundle "$app/Contents/Resources/"
      rcodesign sign --timestamp-url none --signing-time 2001-01-01T00:00:00Z "$app"
      runHook postInstall
    '';
    # Strip/fixup after signing would invalidate the bundle signature.
    dontFixup = true;
    disallowedReferences = [
      toolchain
      sdk
    ];
    meta = {
      description = "A native Moonlander layer overlay for macOS 26+";
      platforms = lib.platforms.darwin;
    };
  };

  # Keep the wrapper's target in a separate, immutable output. Embedding its own
  # $out would make the Mach-O UUID depend on Nix's temporary rebuild path.
  keyfinder =
    pkgs.runCommand "keyfinder-1.0.0"
      {
        nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        meta = appBundle.meta // {
          mainProgram = "keyfinder";
        };
        passthru = { inherit appBundle; };
      }
      ''
        mkdir -p "$out/Applications"
        ln -s ${appBundle}/Applications/Keyfinder.app "$out/Applications/Keyfinder.app"
        makeWrapper ${appBundle}/Applications/Keyfinder.app/Contents/MacOS/Keyfinder "$out/bin/keyfinder"
      '';

  archive =
    pkgs.runCommand "keyfinder-1.0.0-macos-${pkgs.stdenv.hostPlatform.system}.zip"
      {
        nativeBuildInputs = [ pkgs.zip ];
        env.TZ = "UTC";
      }
      ''
        cp -R ${appBundle}/Applications/Keyfinder.app .
        chmod -R u+w Keyfinder.app
        find Keyfinder.app -exec touch -h -t 198001010000.00 {} +
        find Keyfinder.app -print | LC_ALL=C sort | zip -X -q Keyfinder.zip -@
        mv Keyfinder.zip "$out"
      '';

  smoke = pkgs.writeShellApplication {
    name = "keyfinder-smoke-test";
    text = ''
      exec ${lib.getExe keyfinder} --smoke-test "''${1:-$PWD/artifacts/smoke/report.json}"
    '';
  };
  previews = pkgs.writeShellApplication {
    name = "keyfinder-previews";
    text = ''
      exec ${lib.getExe keyfinder} --render-previews "''${1:-$PWD/artifacts/previews}"
    '';
  };
  benchmark = pkgs.writeShellApplication {
    name = "keyfinder-benchmark";
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../scripts/measure-idle.py} \
        --app ${keyfinder}/Applications/Keyfinder.app "$@"
    '';
  };
  app = package: {
    type = "app";
    program = lib.getExe package;
  };
in
{
  inherit keyfinder archive;
  apps = {
    default = app keyfinder;
    smoke-test = app smoke;
    previews = app previews;
    benchmark = app benchmark;
  };
  devShell = pkgs.mkShellNoCC {
    packages = [
      toolchain
      pkgs.nixfmt
      pkgs.python3
      pkgs.rcodesign
    ];
    buildInputs = [ sdk ];
    SDKROOT = sdkPath;
    DEVELOPER_DIR = "${toolchain}";
    SWIFT_EXEC = "${toolchain}/usr/bin/swiftc";
    MACOSX_DEPLOYMENT_TARGET = "26.0";
  };
}
