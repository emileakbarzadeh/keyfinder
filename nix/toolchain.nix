{
  lib,
  stdenvNoCC,
  fetchurl,
  pbzx,
  cpio,
}:

# Nixpkgs currently ships Swift 5.10. Pin Apple's Swift 6 compiler instead of
# discovering Xcode or /Library/Developer/CommandLineTools on the build host.
stdenvNoCC.mkDerivation {
  pname = "apple-command-line-tools";
  version = "26.5";
  src = fetchurl {
    name = "keyfinder-clt-26.5.pkg";
    url = "https://swcdn.apple.com/content/downloads/33/19/140-17812-A_21ZLMMLY4E/zu3xwktttpoe71qiawhzgzvqss6rovawsa/CLTools_Executables_Universal.pkg";
    hash = "sha256-oUhqwgM3lW2VU958TMa/WP570a18HXbexokByW+0Vy4=";
  };
  nativeBuildInputs = [
    pbzx
    cpio
  ];
  unpackPhase = ''
    runHook preUnpack
    pbzx "$src" | cpio -idm --quiet
    runHook postUnpack
  '';
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    cp -R Library/Developer/CommandLineTools "$out"
    ln -s usr/bin "$out/bin"
    runHook postInstall
  '';
  # The upstream executables are signed. Do not strip or rewrite them.
  dontFixup = true;
  meta = {
    description = "Pinned Apple Swift compiler and command line tools for Keyfinder";
    platforms = lib.platforms.darwin;
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
