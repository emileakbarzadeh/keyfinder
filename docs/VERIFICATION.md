# Verification record

Verified September 29, 2026 on macOS 26.6.2, Apple Silicon. The Nix package uses pinned Apple Swift 6.3.3 and macOS SDK 26.4, with Lix 2.93.2. The Moonlander was intentionally unplugged, as authorized by the user.

**Software checks**

| Check | Result |
| --- | --- |
| Core checks | 13 tests, 1,459 assertions passed |
| Core checks plus explicit live Oryx query | 14 tests, 1,461 assertions passed; retrieved `exampleLayout/exampleRevision` with three 72-key layers |
| Nix-packaged release AppKit integration | 35 checks passed, including menu bar visibility and Settings lifecycle |
| Visual inspection | All three keyboard layers and Keyboard, Appearance, and Layout & connection settings pages rendered and reviewed; long legends fitted without dropping layer numbers |
| Standalone packaging | The Nix DMG mounted read-only; both the mounted app and a copy installed outside the store passed signature verification and bundled-layout diagnostics |
| macOS deployment target | `26.0` in both Info.plist and the Mach-O build-version load command |
| Local signature | `codesign --verify --strict` passed; ad-hoc signature |
| App bundle size | 2,203,611 bytes (about 2.10 MiB) |
| Nix runtime closure | 2,257,120 bytes; only the launcher and app bundle, with no compiler or SDK dependency |
| Disk image size | 2,600,960 bytes (about 2.48 MiB), uncompressed |
| Release workflow | `actionlint` passed; native Intel build and actual GitHub release publication remain untested |

The integration checks use the actual AppDelegate, AppModel, repository, preferences, settings views, status item, and NSPanel. Keyboard events, revision-fetch responses, and launch/reopen notifications are simulated. They cover:

- Starting unplugged, offline preview, layer-0 hiding, showing secondary layers, and switching labels.
- Preserving the foreground application and current key window, keeping the panel nonactivating, and setting click-through and Spaces/fullscreen collection behavior.
- Cancelling a pending appearance on return to base, disconnect cleanup, explicit preview, and drag-positioning mode.
- No redraw after 1,000 duplicate hidden-layer reports, no network calls for the bundled revision, and stopping/resuming the USB monitor.
- Keeping live labels unchanged after an Oryx preview refresh, activating the matching revision after a simulated flash/reconnect, and reusing its cache.
- Showing no old key labels for an unavailable new revision, preserving the error across layer changes, and rejecting a late response from an earlier connection.
- Preference persistence and preview cleanup.
- Preserving existing settings when upgrading, hiding and restoring the menu bar icon immediately, and keeping the monitor and overlay active while the icon is hidden.
- Showing Settings on a direct launch with the icon hidden, restoring closed and minimized Settings windows on reopen, and keeping `--background` startup quiet until an explicit reopen.

The executable's `--smoke-test` command returns a nonzero exit code if any check fails. Rendered settings artifacts use AppKit's view rendering and do not require screen recording permission.

**Measured idle performance**

The measurement launched the actual Nix-packaged release app with `--background`, kept Settings closed, and left the keyboard disconnected. After a three-second startup allowance, an external Python process sampled the app's macOS process counters. Measurement timers live in that external tool, not in Keyfinder. Compilation and GUI checks had finished before the measurement began.

| Metric | Observed |
| --- | --- |
| Measurement duration | 30.003 seconds |
| App CPU time during the interval | 0.000065 seconds |
| Average CPU utilization | 0.000218% of one core |
| Resident memory at end | 47.0 MiB |
| Context switches during interval | 15 |
| Mach messages received during interval | 2 |
| Threads at end | 3 |

These observations establish negligible idle work in this configuration; they are not a promise of literally zero CPU use under every condition. Device events, wake/display notifications, UI interaction, and layout downloads perform necessary work. Stock firmware also sends key-position reports, which are discarded in the HID callback without typing analysis or UI work.

A source audit found no repeating timers, polling loops, background URL sessions, global keyboard event taps, or continuous render/display links in the normal app path. The only scheduled delays are a one-shot connection deadline and an optional one-shot overlay appearance delay. Diagnostic sleeps are confined to explicit test commands.

**Checks requiring the physical setup**

Actual USB pairing and layer reports, permission behavior with the Moonlander attached, real firmware flashing, and coexistence with Oryx live training/Keymapp remain untested because the keyboard is unplugged. Source review and packet fixtures support those paths; they do not substitute for a physical-device test.

Sleep/wake observers, display fallback, fullscreen/Spaces configuration, and launch at login are implemented using native APIs. The tests check the panel configuration and simulated lifecycle rather than rebooting the Mac, changing its display hardware, or changing the user's login-item authorization. Verify those integrations on the user's normal desktop setup when connecting the keyboard.

Developer ID signing/notarization was not performed: the Mac has no valid Developer ID signing identity. The Nix-generated app is ad-hoc signed and runs locally. Distribution commands are documented in [Nix packaging](NIX.md#developer-id-signing-and-notarization).

**Nix packaging and reproducibility**

The app and compiler extraction were built with `--option sandbox true`. The compiler, SDK, and signing tool came from pinned store inputs; compilation did not use the host's Xcode or Command Line Tools. The offline core runner executed during the sandboxed build.

`nix build --rebuild` produced identical outputs for the signed app bundle, compiled launcher package, and DMG. The disk image is generated entirely in the Nix sandbox, without mounting a volume or using the host's image-building tools. Its filesystem dates and ownership are fixed, and executable permissions and the app signature survive copying the app out of the image. The app's macOS deployment target is 26.0 and its SDK load command is 26.4. It links only to macOS system frameworks and libraries.

The module checks evaluate real nix-darwin configurations with the service disabled, enabled, configured for manual launch, and given a custom package. They verify installation, Aqua-session startup, `KeepAlive = false`, direct executable arguments, no root daemon, and nix-darwin's own assertions. These checks do not activate a service or modify the host's system configuration.

Apple Silicon was built and run. Intel outputs were evaluated but were not built or run on Intel hardware. Byte-for-byte rebuilds were compared on this Mac; comparison across different machines or macOS versions remains untested.

**Reproduction and artifact identity**

```sh
nix flake check
nix flake check --no-build --all-systems
nix run .#smoke-test
nix run .#previews
nix run .#benchmark -- --seconds 30
nix develop --command swift run KeyfinderCoreChecks --live-oryx
nix build .#dmg --out-link result-dmg
nix build . .#keyfinder.appBundle --rebuild --no-link --option sandbox true
nix build .#dmg --rebuild --no-link --option sandbox true
codesign --verify --strict result/Applications/Keyfinder.app
```

Generated reports and images are in `artifacts/`. The verified release executable SHA-256 is:

```text
e3def7a0ad2acc64bead4ca2a53ce38dfa2c44cbf66b260c9c38fb91e1a286b9
```

The verified DMG SHA-256 is:

```text
5f3f2b729986f5dbfa4422f3b66ee8cf3a89be069179fdaf6db4102f1286cd6c
```
