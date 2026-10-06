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

Measured for v1.1.0 on an M2 Max running macOS 26.6.2. The release build ran with `--background`, Settings closed, and no keyboard connected. `nix run .#benchmark -- --seconds 60` sampled it twice after a 3-second startup allowance; `footprint` and `top` sampled a separate idle run.

| Metric | Run 1 | Run 2 |
| --- | --- | --- |
| CPU time in 60 seconds | 2.7 ms | 4.0 ms |
| Average CPU | 0.0045% of one core | 0.0067% of one core |
| Context switches | 30 | 41 |
| Mach messages received | 4 | 6 |
| Threads | 4 | 4 |

The CPU figures were first published as 65 µs and 97 µs. The benchmark had divided the kernel's CPU counters by 10⁹, but on Apple Silicon they count Mach ticks of 125/3 ns, so those figures were about 42 times too low. The values above convert the same raw counters correctly. The benchmark now converts them and checks its total against `ps` on every run.

| Metric | Observed |
| --- | --- |
| Startup CPU (first 3 seconds) | 0.09 s |
| Memory footprint | 12 MB (resident size 69.6 MiB, including shared system frameworks) |
| Idle wakeups and energy impact (`top`, 60 seconds) | 0 and 0.0 |
| App bundle | 10 MB, including the 7.6 MB Zapp helper |
| Disk image | 4.2 MB |

A source audit found no repeating timers, polling loops, background URL sessions, event taps, or continuous rendering. The only scheduled delays are a one-shot connection deadline and the optional appearance delay.

### Typing and overlay performance

Measured for v1.1.0 on the same Mac with a Moonlander connected. `scripts/measure-performance.py --attach` sampled the installed app once per second while it had been running for 2 days 17 hours, with Settings closed. Each run began with the keyboard untouched, followed by normal typing; the second run also switched layers. Seconds with the overlay on screen, or with 8 or more Mach messages, count as overlay activity. Other seconds with 5 or more context switches count as typing.

| Metric | Run 1 (300 s) | Run 2 (180 s) |
| --- | --- | --- |
| Connected, untouched: CPU | 0.0038% of one core (262 s) | 0.0091% of one core (52 s) |
| Typing: CPU | 0.10% of one core (38 s) | 0.11% of one core (114 s) |
| Typing: energy | 0.17 mW | 0.19 mW |
| Typing: context switches | 17 per second | 25 per second |
| Overlay activity | None | 14 s; 740 ms of CPU and 290 mJ in total |
| Package idle wakeups | 1 | 0 |
| Memory footprint | 44.1 MB throughout | 44.2 MB; 63.7 MB peak while the overlay was visible |

- **Typing:** the median typing second used 1.05 ms of CPU, and the 90th percentile 2 ms.
- **Overlay:** each show or layer change while visible executed about 148 million instructions, 50–75 ms of CPU on the main thread. Each hide executed about 44 million instructions, 20–30 ms. Memory returned to 44.2 MB after the overlay hid.
- **Memory:** this long-running instance had a 44 MB footprint, compared with 12 MB after a fresh launch, and a lifetime peak of 90 MB. Typing did not change it.
- **Periodic wake:** the process woke about every 3 seconds whether or not the keyboard was in use, for 50–120 µs each time. That is 0.35 timer wakeups per second, with almost no package idle wakeups. Keyfinder's source schedules no repeating timer, and a stack sample showed libdispatch servicing a timer. The idle runs' 30–41 context switches per minute are consistent with the same wake.

CPU and energy are those billed to Keyfinder. Kernel USB handling and WindowServer compositing are not included. Reports are written under `artifacts/performance/`.

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
nix run .#benchmark -- --attach --seconds 180
nix build . .#dmg --rebuild --no-link
nix build
codesign --verify --strict result/Applications/Keyfinder.app
```

Reports from the GUI checks are written under `artifacts/`.
