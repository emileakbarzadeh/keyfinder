# Mozilla's maintained libdmg-hfsplus converts the xorriso image into a
# compressed read-only UDIF disk image without hdiutil, which Nix cannot
# package. It runs only at build time; nothing from it ships in the DMG.
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  bzip2,
  zlib,
}:
stdenv.mkDerivation {
  pname = "libdmg-hfsplus";
  version = "0-unstable-2026-01-29";
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "mozilla";
    repo = "libdmg-hfsplus";
    rev = "ec239599c1f234a4e01ae3fe51214d0c77e5baa3";
    hash = "sha256-ajcLwBWy0vIqhSum8WN7Hwd3XA2KiJBk3lgtkHKix90=";
  };

  nativeBuildInputs = [ cmake ];
  buildInputs = [
    bzip2
    zlib
  ];
  # Only the conversion tool is needed. Without these libraries the build
  # also omits encrypted, LZMA, and LZFSE image support.
  cmakeFlags = [
    "-DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL=ON"
    "-DCMAKE_DISABLE_FIND_PACKAGE_LibLZMA=ON"
    "-DCMAKE_DISABLE_FIND_PACKAGE_LZFSE=ON"
  ];
  buildFlags = [ "dmg-bin" ];
  installPhase = ''
    runHook preInstall
    install -Dm755 dmg/dmg "$out/bin/dmg"
    runHook postInstall
  '';

  meta = {
    description = "Portable tools for Apple DMG images";
    homepage = "https://github.com/mozilla/libdmg-hfsplus";
    license = lib.licenses.gpl3Plus;
    mainProgram = "dmg";
    platforms = lib.platforms.unix;
  };
}
