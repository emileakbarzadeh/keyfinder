# Verification

What is checked automatically, what has been checked by hand, and what still needs testing with physical keyboards.

## Automated checks

| Command | Covers |
| --- | --- |
| `nix flake check` | Builds the app with the pinned compiler and SDK, runs the offline core tests and packaging guard tests, and evaluates nix-darwin configurations using the module. |
| `nix run .#smoke-test` | AppKit integration with temporary windows: overlay visibility and focus, layer changes, delayed appearance, preview and arrangement modes, layout synchronization after a simulated flash, appearance changes, menu bar icon, Settings lifecycle, standard and text-editing shortcuts, keyboard models, and preview tooltips. |
| `nix run .#firmware-checks` | Firmware file validation and staging, subprocess output and exit handling, flash lifecycle around USB monitoring, and the Settings preview following a flashed revision. Uses a separate fake backend with no USB code; it never runs the real Zapp. |
| `swift run Keyfinder --check-shortcuts report.json` | Hold-shortcut migration, recording, registration, and release behavior. |
| Release workflow | Builds both architectures from a tag, runs `nix flake check`, verifies the disk image's checksums, mounts it, verifies the app and helper signatures, checks Zapp's standalone dependencies, and runs the app's offline diagnostics. |

The GUI checks need a logged-in macOS session and write a JSON report; the command exits nonzero if any check fails. Keyboard events, Oryx responses, and Zapp runs are simulated with fixtures. The bundled demo layout is synthetic, so no check depends on an Oryx account.

## Checked by hand

- **Rendering:** all keyboard layers, all three keyboard models, and every Settings page in Light and Dark.
- **Contrast** (sRGB, opaque backgrounds): parchment on charcoal 16.76:1, dark text on parchment 14.21:1, charcoal on orange 7.09:1, parchment on red 4.51:1. Secondary key labels stay at or above 4.59:1 with the darkest and lightest Oryx key colors. The adjustable overlay opacity changes contrast against the desktop.
- **Permissions:** the app has no entitlements or privacy usage declarations. Its binary imports `RegisterEventHotKey` and none of `CGEventTapCreate`, `AXIsProcessTrustedWithOptions`, `IOHIDRequestAccess`, or `CGRequestScreenCaptureAccess`.
- **Disk image:** opening it in Finder mounts it read-only and shows the drag-to-Applications window. The copied app passes `codesign --verify --deep --strict`.
- **Reproducibility:** `nix build --rebuild` produces identical app, launcher, and disk image outputs on Apple Silicon.

### Idle performance

Measured with `nix run .#benchmark -- --seconds 30` on Apple Silicon and macOS 26, using the release build with Settings closed and no keyboard connected:

| Metric | Observed |
| --- | --- |
| Average CPU | 0.000164% of one core |
| Resident memory | 46.4 MiB |
| Context switches | 19 in 30 seconds |
| Threads | 3 |

This predates multi-model support and the bundled Zapp helper. It excludes startup, a connected keyboard, and a visible overlay. A source audit found no repeating timers, polling loops, background URL sessions, event taps, or continuous rendering. The only scheduled delays are a one-shot connection deadline and the optional appearance delay.

## Not yet verified

- **Physical keyboards:** USB pairing, live layer reports, and flash/reconnect behavior. Voyager and ErgoDox EZ key positions are schematic and need checking against the real keyboards.
- **Firmware flashing:** Zapp's reset flow, compatibility checks, and recovery with real hardware.
- **Hold shortcut:** a physical F18 press and release.
- **Coexistence:** running alongside Oryx live training or Keymapp.
- **System integration:** launch at login, display changes, and Spaces/fullscreen behavior on a real desktop.
- **Intel:** release builds are produced on GitHub's Intel runners but have not been run on Intel hardware.
- **Reproducibility across machines:** byte-for-byte rebuilds have only been compared on one Mac.

Developer ID signing and notarization are not configured. See [Nix packaging](NIX.md#developer-id-signing-and-notarization).

## Reproduce

```sh
nix flake check
nix run .#smoke-test
nix run .#firmware-checks
nix run .#benchmark -- --seconds 30
nix build . .#dmg --rebuild --no-link
nix build
codesign --verify --strict result/Applications/Keyfinder.app
```

Reports from the GUI checks are written under `artifacts/`.
