# Backport Zapp 1.0.2's Nixpkgs package to the 26.05 Darwin pin, which still
# supports Intel Macs. Source and Cargo hashes come from that upstream package.
{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  udev,
  versionCheckHook,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "zapp";
  version = "1.0.2";
  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "zsa";
    repo = "zapp";
    tag = "v${finalAttrs.version}";
    hash = "sha256-K+L8Hyw8BFyYoHGofRJrZqwTwth3Q2ypAq3uj8rO57I=";
  };
  cargoHash = "sha256-4MhPi6Ej37M+O7OE5sgzS7zhUhgawLEwxkNRSadwVcI=";
  # indicatif suppresses prompts and progress when Keyfinder captures a pipe.
  patches = [ ./patches/zapp-piped-progress.patch ];
  nativeBuildInputs = [ pkg-config ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ udev ];
  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  meta = {
    description = "Flash ZSA keyboards from your terminal";
    homepage = "https://github.com/zsa/zapp";
    license = with lib.licenses; [
      mit
      commons-clause
    ];
    mainProgram = "zapp";
  };
})
