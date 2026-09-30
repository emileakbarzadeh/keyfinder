# Nix packaging

Nix is the primary build and packaging interface. The repository has no standalone shell build scripts. The derivations declare the source files, compiler, SDK, build checks, app contents, signing tool, disk image, development environment, and login service. Short build phases perform compilation and file installation. The app's CLI launcher is a compiled executable; the optional diagnostic command wrappers contain only an `exec`.

## Inputs and outputs

`flake.lock` pins Nixpkgs and nix-darwin to their 26.05 Darwin branches. This keeps both `aarch64-darwin` and `x86_64-darwin` evaluable; later Nixpkgs releases have dropped Intel Mac support. Linux has no app package yet.

Nixpkgs' Swift compiler is currently too old for the app. [toolchain.nix](../nix/toolchain.nix) fetches Apple's Command Line Tools 26.5 package by SHA-256 and extracts it into the store without running its installer. It contains Swift 6.3.3, a pinned upstream binary rather than a compiler rebuilt from source. Only this named dependency is allowed by the flake's unfree-package predicate; Apple's toolchain terms still apply.

The macOS 26.4 SDK comes from the locked Nixpkgs `apple-sdk_26.src` output. Using that original SDK preserves the SwiftShims headers that Nixpkgs' processed SDK removes for its own older Swift package. Both compiler and SDK are downloaded into the store; neither is read from the build host's Xcode installation.

| Flake output | Use |
| --- | --- |
| `packages.<system>.default` / `keyfinder` | Release `.app` under `Applications`, plus `bin/keyfinder` |
| `packages.<system>.dmg` | Mountable disk image containing the standalone `.app` and an Applications shortcut |
| `apps.<system>.default` | Launch the app; arguments pass through unchanged |
| `apps.<system>.smoke-test` | AppKit checks with temporary windows and simulated USB events |
| `apps.<system>.previews` | Render the bundled keyboard layers |
| `apps.<system>.demo` | Generate the README GIF from the app's synthetic previews |
| `apps.<system>.benchmark` | External CPU and memory measurement of the packaged app |
| `checks.<system>.package` | Build the release app and run offline core checks |
| `checks.<system>.module` | Evaluate actual nix-darwin configurations and check their generated service settings |
| `devShells.<system>.default` | Pinned Swift/SDK, Python, signing tool, and Nix formatter |
| `formatter.<system>` | `nixfmt` |
| `darwinModules.default` / `keyfinder` | nix-darwin service module |
| `overlays.default` | Expose the flake's pinned package as `pkgs.keyfinder` |

There are no third-party Swift package dependencies. The source filter excludes docs, screenshots, Git state, and build artifacts, so documentation changes do not rebuild the app.

The signed app bundle and compiled launcher use separate store outputs. The default package links to the complete bundle under `Applications/Keyfinder.app`, preserving its signature. Use the disk image, or `cp -RL result/Applications/Keyfinder.app destination`, when copying a standalone app out of the store.

## Building and verifying

```sh
nix build
nix flake check
nix flake check --no-build --all-systems
nix run . -- --diagnostics
nix run .#smoke-test
nix run .#previews
nix run .#demo
nix run .#benchmark -- --seconds 30 --output artifacts/idle-performance.json
nix build .#dmg --out-link result-dmg
```

The package's offline core checks run inside the build. GUI checks, preview rendering, and performance measurements run explicitly in your desktop session. They are not cached as build-time test results, and they do not run during system activation. The smoke command accepts an optional report path; previews accepts an optional output directory. Alongside the bundled layers, previews renders a selected key and unverified-revision badge with Oryx colors disabled. Relative paths resolve from the directory where you invoke Nix.

The benchmark starts its own app process and terminates only that process. Disconnect the keyboard and keep Settings closed when measuring the unplugged idle baseline. Reports are observations of the host and cannot be reproduced as fixed derivation outputs.

The demo generator uses the packaged app's AppKit renderer, then composes a nine-second GIF with pinned Python, Pillow, and Inter fonts. It illustrates layers 1 and 2 followed by the hidden overlay on layer 0; it does not record the desktop or connect to a keyboard. These documentation tools add no dependencies to the installed app. Rendering runs in a graphical macOS session, so the GIF is a generated documentation asset rather than a sandboxed build output. To refresh the README asset:

```sh
nix run .#demo -- --output docs/assets/demo.gif
```

For development:

```sh
nix develop
swift build
swift run KeyfinderCoreChecks
```

Core checks use synthetic fixtures and do not contact Oryx. To check the service explicitly, run `swift run KeyfinderCoreChecks --live-oryx '<exact-revision Moonlander URL>'` with a URL you choose; `latest` URLs are rejected so the expected identity is unambiguous. No account or layout URL is built into the test runner.

To update pinned dependencies, run `nix flake update`, review `flake.lock`, then rebuild and rerun checks. Updating the compiler also requires reviewing the URL and content hash in `nix/toolchain.nix`.

## Reproducibility

The build selects the compiler and SDK from store paths, uses a fixed macOS 26.0 deployment target, omits debug information, and enables the linker's reproducible mode with content-derived UUIDs. Resources resolve beside the executable or inside the app, without embedding SwiftPM's absolute build-directory fallback. The checked-in icon is a release asset, so building the app never needs a graphical session to render it.

The signing tool is pinned and signs ad hoc without a timestamp server, using a fixed signing time. The package rejects references to its compiler or SDK, keeping those build inputs out of the runtime closure. macOS frameworks and services remain runtime dependencies supplied by the operating system.

[dmg.nix](../nix/dmg.nix) uses pinned `xorriso`/`libisofs` to create an uncompressed HFS+/ISO hybrid disk image with fixed file dates, ownership, volume dates, and a content-derived volume identifier. It needs no disk mounting or host `hdiutil` during the Nix build. A small scoped patch prevents `libisofs` from inventing Finder type/creator metadata, which would invalidate the app's signature. The image preserves the signed app and includes an Applications shortcut for drag-and-drop installation. macOS mounts it directly as a `.dmg`; it is not a ZIP archive.

Pinned inputs and deterministic packaging make repeatable builds possible. Actual rebuild comparisons, architectures built, and remaining limitations belong in the [verification record](VERIFICATION.md); evaluation alone is not evidence of byte-for-byte reproducibility.

## nix-darwin module

Import `keyfinder.darwinModules.default` and set `services.keyfinder.enable = true`. The module installs the app through `environment.systemPackages`; nix-darwin links it under `/Applications/Nix Apps`.

By default, a LaunchAgent starts the app with `--background` in `system.primaryUser`'s Aqua session. Its `ProgramArguments` point directly at the executable: there is no service shell script, root daemon, polling interval, or restart loop. `KeepAlive = false` means choosing Quit works. Startup also occurs when nix-darwin loads or reloads the agent during activation.

```nix
services.keyfinder = {
  enable = true;
  startAtLogin = false; # Install only; open the app manually.
  # package = anotherKeyfinderPackage;
};
```

Keep the app's own launch-at-login toggle disabled while the module manages startup. If you previously enabled that toggle, turn it off before enabling the module's agent. macOS privacy permissions remain user-controlled; installation does not grant Input Monitoring access.

The default package uses Keyfinder's locked Nixpkgs even if the containing system uses another revision. There is no need to set `keyfinder.inputs.nixpkgs.follows`; doing so transfers responsibility for SDK and tool compatibility to the containing configuration.

Removing or disabling the module removes its declarative installation and LaunchAgent on the next rebuild. Personal preferences and cached layouts remain in the user's Library.

## Tag releases

The [release workflow](../.github/workflows/release.yml) runs whenever a Git tag is pushed. It builds natively on macOS 26 for Apple Silicon and Intel, runs `nix flake check`, and builds the `dmg` output with the checked-in lock file and Nix sandbox enabled. It mounts each image read-only, verifies the app's signature, runs its offline diagnostics outside the Nix store, and detaches the image.

Once both builds pass, it publishes a GitHub release with generated release notes and two downloads:

| Asset | Mac |
| --- | --- |
| `Keyfinder-macOS-arm64.dmg` | Apple Silicon (M-series) |
| `Keyfinder-macOS-x86_64.dmg` | Intel |

Each disk image contains a standalone `Keyfinder.app`; users do not need Nix. Packaging stays in Nix, and the workflow uploads the image unchanged, with artifact ZIP wrapping disabled. All actions are pinned to commit hashes. Only the publishing job receives `contents: write`; the built-in `GITHUB_TOKEN` is sufficient, with no additional secrets needed.

Before tagging a new version, update `Packaging/Info.plist` and the app version in `nix/packages.nix`, and commit those changes together. The launcher and disk image inherit that package version. The tag selects that committed source; the workflow does not rewrite version metadata or update `flake.lock`. For example, after the workflow and version changes are on GitHub:

```sh
git tag v1.0.0
git push origin v1.0.0
```

Every pushed tag creates a regular release; branch pushes and tag deletions do not publish. New releases are published after both assets upload. Failed runs can be retried from GitHub Actions; on repositories with mutable releases, rerunning a published tag replaces assets with the same names. Immutable releases require a new tag after publication.

These automated downloads use the reproducible ad-hoc signature. Developer ID signing and notarization are not configured. macOS may require **System Settings → Privacy & Security → Open Anyway** for a downloaded app.

## Developer ID signing and notarization

Nix outputs are immutable. Copy the built app out of the store before applying your Developer ID signature and notarizing it with Apple's tools:

```sh
cp -RL result/Applications/Keyfinder.app ./Keyfinder.app
chmod -R u+w ./Keyfinder.app
codesign --force --options runtime --timestamp \
  --sign 'Developer ID Application: Your Name (TEAMID)' ./Keyfinder.app
mkdir -p ./release-content
cp -R ./Keyfinder.app ./release-content/
ln -s /Applications ./release-content/Applications
hdiutil create -volname Keyfinder -srcfolder ./release-content -format UDRO ./Keyfinder-macOS.dmg
codesign --sign 'Developer ID Application: Your Name (TEAMID)' --timestamp ./Keyfinder-macOS.dmg
xcrun notarytool submit ./Keyfinder-macOS.dmg --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple ./Keyfinder-macOS.dmg
```

Developer ID signing and notarization depend on external credentials and Apple's service, and are intentionally outside the reproducible local package. The normal Nix build requires neither.
