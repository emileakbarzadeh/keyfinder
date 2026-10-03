# Nix packaging

Nix is the primary build and packaging interface. The repository has no standalone shell build scripts. The derivations declare the source files, compiler, SDK, build checks, app contents, signing tool, disk image, development environment, and login service. Short build phases perform compilation and file installation. The app's CLI launcher is a compiled executable; the optional diagnostic command wrappers contain only an `exec`.

## Inputs and outputs

`flake.lock` pins Nixpkgs and nix-darwin to their 26.05 Darwin branches. This keeps both `aarch64-darwin` and `x86_64-darwin` evaluable; later Nixpkgs releases have dropped Intel Mac support. Linux has no app package yet.

Nixpkgs' Swift compiler is currently too old for the app. [toolchain.nix](../nix/toolchain.nix) fetches Apple's Command Line Tools 26.5 package by SHA-256 and extracts it into the store without running its installer. It contains Swift 6.3.3, a pinned upstream binary rather than a compiler rebuilt from source. The unfree-package predicate allows only this toolchain and Zapp. Apple's toolchain terms and Zapp's upstream license apply to those dependencies.

The macOS 26.4 SDK comes from the locked Nixpkgs `apple-sdk_26.src` output. Using that original SDK preserves the SwiftShims headers that Nixpkgs' processed SDK removes for its own older Swift package. Both compiler and SDK are downloaded into the store; neither is read from the build host's Xcode installation.

| Flake output | Use |
| --- | --- |
| `packages.<system>.default` / `keyfinder` | Release `.app` under `Applications`, plus `bin/keyfinder` |
| `packages.<system>.dmg` | Compressed disk image that opens a drag-to-Applications window |
| `apps.<system>.default` | Launch the app; arguments pass through unchanged |
| `apps.<system>.smoke-test` | AppKit checks with temporary windows and simulated USB events |
| `apps.<system>.firmware-checks` | File validation, subprocess output, and flash lifecycle checks using a separate fake backend |
| `apps.<system>.previews` | Render the bundled keyboard layers |
| `apps.<system>.demo` | Generate the README GIF from the app's synthetic previews |
| `apps.<system>.benchmark` | External CPU and memory measurement of the packaged app |
| `checks.<system>.package` | Build the release app and run offline core checks |
| `checks.<system>.module` | Evaluate actual nix-darwin configurations and check their generated service settings |
| `devShells.<system>.default` | Pinned Swift/SDK, Zapp, Python, signing tool, and Nix formatter |
| `formatter.<system>` | `nixfmt` |
| `darwinModules.default` / `keyfinder` | nix-darwin service module |
| `overlays.default` | Expose the flake's pinned package as `pkgs.keyfinder` |

There are no third-party Swift package dependencies. The source filter excludes docs, screenshots, Git state, and build artifacts, so documentation changes do not rebuild the app.

The signed app bundle and compiled launcher use separate store outputs. The default package links to the complete bundle under `Applications/Keyfinder.app`, preserving its signature. Use the disk image, or `cp -RL result/Applications/Keyfinder.app destination`, when copying a standalone app out of the store.

[zapp.nix](../nix/zapp.nix) backports the Nixpkgs Zapp 1.0.2 package, with its fixed source and Cargo dependency hashes, to Keyfinder’s 26.05 Darwin toolchain. That branch does not include Zapp; keeping it allows Intel builds. The app derivation copies the executable into `Contents/Helpers/zapp`, includes its upstream license files, and signs the helper before signing the app. The module and disk image carry this same bundle; enabling `programs.zapp` separately is unnecessary.

[zapp-piped-progress.patch](../nix/patches/zapp-piped-progress.patch) makes Zapp print its bootloader/reset instruction and progress when its terminal display is hidden, including in Keyfinder’s captured output. It includes a regression test that renders progress in a subprocess with piped output and no USB access. The patch applies to the bundled helper and the development shell’s Zapp.

[check-zapp-bundle.py](../scripts/check-zapp-bundle.py) rejects non-system dynamic libraries and Nix store paths in the helper’s Mach-O load commands. It also runs only `zapp --help` to check that the flash command is present. The build fails if the upstream package gains dependencies that would prevent it running outside the store. Zapp’s license is MIT with the Commons Clause, as recorded by Nixpkgs; the bundled upstream files retain its terms.

Zapp’s Nix build links to Darwin `libiconv`. During app installation, the derivation changes that load command to `/usr/lib/libiconv.2.dylib`, supplied by macOS with the same version-7 ABI. It then signs the modified helper before running the standalone check. The bundle rejects references to Nix’s `libiconv` output as well as the original Zapp package.

## Building and verifying

```sh
nix build
nix flake check
nix flake check --no-build --all-systems
nix run . -- --diagnostics
nix run .#smoke-test
nix run .#firmware-checks
nix run .#previews
nix run .#demo
nix run .#benchmark -- --seconds 30 --output artifacts/idle-performance.json
nix build .#dmg --out-link result-dmg
```

The package's offline core checks run inside the build. GUI checks, preview rendering, and performance measurements run explicitly in your desktop session. They are not cached as build-time test results, and they do not run during system activation. The smoke command accepts an optional report path; previews accepts an optional output directory. Previews renders each bundled layer in Light and Dark, plus a selected key and unverified-revision subtitle with Oryx colors disabled. Light assets use a `-light` filename suffix. The command also renders numbered Voyager and ErgoDox EZ diagrams for checking key positions. Relative paths resolve from the directory where you invoke Nix.

The benchmark starts its own app process and terminates only that process. Disconnect the keyboard and keep Settings closed when measuring the unplugged idle baseline. Reports are observations of the host and cannot be reproduced as fixed derivation outputs.

The demo generator uses the packaged app's AppKit renderer, then composes a nine-second GIF with pinned Python, Pillow, and Inter fonts. It illustrates layers 1 and 2 followed by the hidden overlay on layer 0; it does not record the desktop or connect to a keyboard. These documentation tools add no dependencies to the installed app. Rendering runs in a graphical macOS session, so the GIF is a generated documentation asset rather than a sandboxed build output. To refresh the README asset:

```sh
nix run .#demo -- --output docs/assets/demo.gif
nix run .#demo -- --appearance light --output docs/assets/demo-light.gif
```

For development:

```sh
nix develop
swift build
swift run KeyfinderCoreChecks
```

Core checks use synthetic fixtures and do not contact Oryx. To check the service explicitly, run `swift run KeyfinderCoreChecks --live-oryx '<exact-revision Oryx URL>'` with a URL you choose; `latest` URLs are rejected so the expected identity is unambiguous. No account or layout URL is built into the test runner.

Run `nix run . -- --check-shortcuts artifacts/shortcut-checks/report.json` for the hold-shortcut checks without the full desktop focus suite. It checks preferences, the Settings recorder, held-layer behavior, and native hotkey registration and callbacks. Synthetic events stay within the test process; it does not inject system keystrokes or request input-monitoring permissions. The full smoke suite also includes these checks.

The firmware checks use `KeyfinderZappFixture`, built into a separate `testHelpers` output and excluded from the `.app` and DMG. It has no USB code. The checks exercise staging, lifecycle transitions, and actual subprocess pipes, then render the Firmware tab in both themes. They never invoke the real Zapp or flash hardware. For a SwiftPM build, run `swift run Keyfinder --check-firmware artifacts/firmware-checks/report.json .build/debug/KeyfinderZappFixture` after `swift build`.

To update pinned dependencies, run `nix flake update`, review `flake.lock`, then rebuild and rerun checks. Updating the compiler also requires reviewing the URL and content hash in `nix/toolchain.nix`. Update Zapp’s version, source hash, and Cargo hash together in `nix/zapp.nix`, then verify its standalone dependencies and CLI contract before releasing.

## Reproducibility

The build selects the compiler and SDK from store paths, uses a fixed macOS 26.0 deployment target, omits debug information, and enables the linker's reproducible mode with content-derived UUIDs. Resources resolve beside the executable or inside the app, without embedding SwiftPM's absolute build-directory fallback. The checked-in icon is a release asset, so building the app never needs a graphical session to render it.

The signing tool is pinned and signs ad hoc without a timestamp server, using a fixed signing time. The package rejects references to its compiler or SDK, keeping those build inputs out of the runtime closure. macOS frameworks and services remain runtime dependencies supplied by the operating system.

[dmg.nix](../nix/dmg.nix) uses pinned `xorriso`/`libisofs` to create an HFS+/ISO hybrid disk image with fixed file dates, ownership, volume dates, and a content-derived volume identifier. A small scoped patch prevents `libisofs` from inventing Finder type/creator metadata, which would invalidate the app's signature. The image preserves the signed app and includes an Applications shortcut for drag-and-drop installation.

When it mounts, Finder opens a window with the app on the left, an arrow, and Applications on the right. Finder normally records that layout in `.DS_Store` while a volume is mounted. [dmg-layout.py](../scripts/dmg-layout.py) writes the same records directly with the pinned `ds_store`, `mac_alias`, and Pillow packages. It also draws the 1x/2x background TIFF. The background uses Keyfinder's light palette because Finder always draws windows with a background picture in Light mode.

Finder opens a window automatically only for read-only UDIF images, not for the raw image `xorriso` writes. Apple's `hdiutil` is part of macOS and cannot be packaged, so [libdmg-hfsplus.nix](../nix/libdmg-hfsplus.nix) builds Mozilla's maintained libdmg-hfsplus to convert the image to zlib-compressed UDIF (UDZO). The converter runs only at build time. Its segment identifier comes from an unseeded `rand()`, keeping the output deterministic. The build never mounts a disk or calls host tools.

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

Keep the app's own launch-at-login toggle disabled while the module manages startup. If you previously enabled that toggle, turn it off before enabling the module's agent. The hold shortcut needs no Accessibility or Input Monitoring access, and installation changes no macOS privacy settings.

The default package uses Keyfinder's locked Nixpkgs even if the containing system uses another revision. There is no need to set `keyfinder.inputs.nixpkgs.follows`; doing so transfers responsibility for SDK and tool compatibility to the containing configuration.

Removing or disabling the module removes its declarative installation and LaunchAgent on the next rebuild. Personal preferences and cached layouts remain in the user's Library.

## Tag releases

The [release workflow](../.github/workflows/release.yml) runs whenever a Git tag is pushed. It builds natively on macOS 26 for Apple Silicon and Intel, runs `nix flake check`, and builds the `dmg` output with the checked-in lock file and Nix sandbox enabled. It checks each image's checksums with `hdiutil verify`, mounts it read-only, verifies the app and nested helper signatures, checks Zapp’s standalone dependencies and help output, runs the app’s offline diagnostics outside the Nix store, and detaches the image.

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
  --sign 'Developer ID Application: Your Name (TEAMID)' ./Keyfinder.app/Contents/Helpers/zapp
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
