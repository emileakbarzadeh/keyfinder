# Verification record

Baseline verified at commit `6692652` on September 30, 2026, macOS 26.6.2, Apple Silicon. The Nix package uses pinned Apple Swift 6.3.3 and macOS SDK 26.4, with Lix 2.93.2. Checks use synthetic layout fixtures and simulated keyboard events; no Moonlander was connected.

**Software checks**

| Check | Result |
| --- | --- |
| Core checks | 13 tests, 1,460 assertions passed |
| Core checks plus explicit live Oryx query | 14 tests, 1,462 assertions passed using a supplied exact-revision URL; no preset account or layout in the runner |
| Nix-packaged release AppKit integration | 48 checks passed, including appearance changes, preference migration, menu bar visibility, and Settings lifecycle |
| Visual inspection | All three keyboard layers and settings pages rendered and reviewed in Light and Dark, including selected keys, disabled Oryx colors, and the unverified-revision badge |
| Standalone packaging | The Nix DMG mounted read-only; both the mounted app and a copy installed outside the store passed signature verification and bundled-layout diagnostics |
| macOS deployment target | `26.0` in both Info.plist and the Mach-O build-version load command |
| Local signature | `codesign --verify --strict` passed; ad-hoc signature |
| App bundle size | 2,014,685 bytes (about 1.92 MiB) |
| Nix runtime closure | 2,068,176 bytes; only the launcher and app bundle, with no compiler or SDK dependency |
| Disk image size | 2,412,544 bytes (about 2.30 MiB), uncompressed |
| Release workflow | `actionlint` passed; native Intel build and actual GitHub release publication remain untested |

The integration checks use the actual AppDelegate, AppModel, repository, preferences, settings views, status item, and NSPanel. Keyboard events, revision-fetch responses, and launch/reopen notifications are simulated. They cover:

- Starting unplugged, offline preview, layer-0 hiding, showing secondary layers, and switching labels.
- Starting with no preset Oryx URL, keeping the synthetic demo separate from real keyboard associations, and initializing the preview from the first identified layout.
- Preserving the foreground application and current key window, keeping the panel nonactivating, and setting click-through and Spaces/fullscreen collection behavior.
- Cancelling a pending appearance on return to base, disconnect cleanup, explicit preview, and drag-positioning mode.
- No redraw after 1,000 duplicate hidden-layer reports, no network calls for the bundled revision, and stopping/resuming the USB monitor.
- Keeping live labels unchanged after an Oryx preview refresh, activating the matching revision after a simulated flash/reconnect, and reusing its cache.
- Showing no old key labels for an unavailable new revision, preserving the error across layer changes, and rejecting a late response from an earlier connection.
- Preference persistence and preview cleanup.
- Switching Settings and the visible overlay between Light, Dark, and System; following inherited appearance changes; restoring the saved choice on launch; and accepting older or unknown theme preferences without resetting other settings.
- Skipping hidden-overlay rendering during a system theme change, then drawing the current theme when shown again.
- Preserving existing settings when upgrading, hiding and restoring the menu bar icon immediately, and keeping the monitor and overlay active while the icon is hidden.
- Showing Settings on a direct launch with the icon hidden, restoring closed and minimized Settings windows on reopen, and keeping `--background` startup quiet until an explicit reopen.

The executable's `--smoke-test` command returns a nonzero exit code if any check fails. Rendered settings artifacts use AppKit's view rendering and do not require screen recording permission.

Text contrast was checked in sRGB on opaque backgrounds: parchment on charcoal is 16.76:1, dark text on parchment is 14.21:1, charcoal on orange is 7.09:1, and parchment on red is 4.51:1. Secondary key labels remain at least 4.59:1 across both themes, including the darkest and lightest possible Oryx tints. The overlay's user-adjustable opacity can change contrast against the desktop. The README GIF converts AppKit captures to sRGB before encoding.

**Measured idle performance**

The measurement launched the actual Nix-packaged release app with `--background`, kept Settings closed, and left the keyboard disconnected. After a three-second startup allowance, an external Python process sampled the app's macOS process counters. Measurement timers live in that external tool, not in Keyfinder. Compilation and GUI checks had finished before the measurement began.

| Metric | Observed |
| --- | --- |
| Measurement duration | 30.009 seconds |
| App CPU time during the interval | 0.000049 seconds |
| Average CPU utilization | 0.000164% of one core |
| Resident memory at end | 46.4 MiB |
| Context switches during interval | 19 |
| Mach messages received during interval | 2 |
| Threads at end | 3 |

These observations establish negligible idle work in this configuration; they are not a promise of literally zero CPU use under every condition. Device events, wake/display notifications, UI interaction, and layout downloads perform necessary work. Stock firmware also sends key-position reports, which are discarded in the HID callback without typing analysis or UI work.

A source audit found no repeating timers, polling loops, background URL sessions, global keyboard event taps, or continuous render/display links in the normal app path. The only scheduled delays are a one-shot connection deadline and an optional one-shot overlay appearance delay. Diagnostic sleeps are confined to explicit test commands.

**Checks requiring the physical setup**

Actual USB pairing and layer reports, permission behavior with the Moonlander attached, real firmware flashing, and coexistence with Oryx live training/Keymapp remain untested because the keyboard is unplugged. Source review and packet fixtures support those paths; they do not substitute for a physical-device test.

Sleep/wake observers, display fallback, fullscreen/Spaces configuration, and launch at login are implemented using native APIs. The tests check panel configuration and simulated lifecycle. Rebooting, display changes, login-item authorization, and firmware updates still require hardware acceptance on a representative desktop setup.

Developer ID signing and notarization are not configured. The Nix-generated app is ad-hoc signed and runs locally. Distribution commands are documented in [Nix packaging](NIX.md#developer-id-signing-and-notarization).

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
nix develop --command swift run KeyfinderCoreChecks --live-oryx '<exact-revision Moonlander URL>'
nix build .#dmg --out-link result-dmg
nix build . .#keyfinder.appBundle --rebuild --no-link --option sandbox true
nix build .#dmg --rebuild --no-link --option sandbox true
codesign --verify --strict result/Applications/Keyfinder.app
```

Generated reports and images are in `artifacts/`. The verified release executable SHA-256 is:

```text
1877b4b532b11205c9a7a17281437a4fa7a8dcdeda5761333c67f08893c6f95c
```

The verified DMG SHA-256 is:

```text
3d6d3841fef24da98697decc01e0da46a352fd574a4fd1d72f7f074b4f7fd2f9
```

**Multiple keyboard models**

The model generalization compiled with the pinned Swift 6.3.3 compiler and macOS 26.4 SDK. Core verification passed 16 tests and 4,721 assertions. All 13 model-specific AppModel checks passed: names, geometry changes, preview/live separation, rejecting incompatible manual associations, and restoring a saved model. The full desktop suite timed out during window activation in the restricted test session; its report retains `passed: false`. The local app bundle passed signature verification, but launching it here aborted during macOS application registration before Keyfinder initialized.

All three models render offscreen in Light and Dark. Voyager and ErgoDox EZ use schematic drawings in Oryx key order; their key positions, USB pairing, and live Oryx responses still require verification against the actual keyboards. The earlier bundle sizes, performance measurements, signatures, and reproducibility checks above describe the baseline build, not this change.

**Transparent overlay — October 1, 2026**

The overlay presentation change compiled with the pinned toolchain. Twelve offscreen renders cover all three keyboard models and both themes. Image alpha checks confirmed transparent gaps and empty badge/footer areas while keycaps remain opaque. README previews and animations were refreshed, and the local app bundle passed signature verification. Desktop activation remains subject to the restricted-session limitation above.

**Overlay glow — October 1, 2026**

The glow change compiled with the pinned toolchain. Twelve offscreen renders confirmed the added glow in both themes, with transparent corners and center gaps and no status badge. The headings and keys were visually checked over bright and dark backgrounds containing text. The README assets were refreshed, and the local app bundle passed signature verification. The glow uses existing redraws; no animation or timer was added. Live desktop activation remains unverified in this restricted session.

**Configurable hold shortcut — October 1, 2026**

The shortcut implementation compiled with the pinned toolchain, and the 16 core tests (4,721 assertions) passed. The dedicated shortcut command passed 33 checks covering preference migration, recording and cancellation, saved bindings, repeat handling, immediate layer-0 display, release, installed-versus-preview layouts, disconnect, pause, sleep/session transitions, shutdown, and simulated registration errors.

Native `RegisterEventHotKey` registration returned `eventInternalErr` (-9868) in this restricted session, which also reports unavailable macOS application services. The command retains `passed: false`; native conflict and press/release callback checks require an ordinary desktop session. The full smoke suite reached its window-activation timeout. A physical F18 press and release remains unverified here.

The Settings controls were rendered in both themes. The Input Monitoring usage declaration, settings link, and permission-grant guidance were removed. Source inspection found no event taps, global event monitors, input-access request calls, or Accessibility/Screen Recording permission requests. The shortcut uses registered hotkey events; its recorder uses its own window’s responder events. These checks do not establish hardware USB access behavior, which still needs physical-device verification.

The local app bundle passed signature verification with no entitlements or privacy usage declarations. Its binary imports `RegisterEventHotKey`; checks found no imports of `CGEventTapCreate`, `AXIsProcessTrustedWithOptions`, `IOHIDRequestAccess`, or `CGRequestScreenCaptureAccess`.

**Firmware flashing — October 1, 2026**

The app compiles with the pinned Swift compiler and SDK. The 16 core tests (4,721 assertions) pass. All 32 firmware checks pass using a simulated keyboard and a separate subprocess fixture with no USB code. They cover file validation and copying, checksums, stale selections, explicit start, USB handoff, pause/session restoration, launch failures, exit status and signals, literal paths, bounded output, and short prompts arriving before the process exits. The prompt test caught buffering in Foundation’s pipe reader; the production reader now uses a single POSIX read per chunk.

The Firmware tab was rendered and inspected in Light and Dark. The earlier shortcut suite still passes its 33 model/recorder checks; native registration continues to fail with -9868 in this restricted session. The app adds no privacy usage declarations or permission-request APIs for file selection or flashing.

Eight packaging guard tests pass using mocked tool output. They check that the helper is copied into the app, retains its license, advertises the `flash` subcommand, and has no external or Nix-store dynamic dependencies. The production guard invokes only `zapp --help`; the test fixture is excluded from the app and DMG.

The cached Nixpkgs 26.05 source was hashed and matched `flake.lock`. The app and Zapp derivations evaluate for `aarch64-darwin` and `x86_64-darwin` using that source and a workspace-local evaluation store. Zapp 1.0.2 is backported from the newer Nixpkgs package with its published source and Cargo hashes; 26.05 itself does not contain Zapp.

The real Zapp executable and a new app/DMG containing it could not be built or exercised here: network resolution and the system Nix daemon are unavailable. The CLI’s physical reset flow, firmware compatibility checks, recovery, and USB permission behavior still need hardware acceptance. No keyboard was flashed. Earlier signed-bundle and size measurements describe builds before Zapp was bundled.

**Standalone Zapp packaging fix — October 1, 2026**

A subsequent Nix build produced Zapp 1.0.2 and exposed its dependency on Nix’s Darwin `libiconv-113`. The app install phase now changes that load command to `/usr/lib/libiconv.2.dylib`. Both libraries declare compatibility/current version 7, and the pinned macOS SDK supplies that ABI. The modified helper is signed before its help command runs.

The dependency checker also excludes `otool`’s first output line, which names the inspected executable. A bundle built in the Nix store must not fail merely because that header contains its own store path. Actual library and runpath references remain checked. All ten packaging guard tests pass, including regressions for Nix `libiconv` rejection, system `libiconv` acceptance, and the output-path header.

Using the real Nix-built Zapp binary and cached Swift build, a standalone app was assembled in the workspace with the same install, rewrite, and signing steps. Its helper passes the production dependency/help check, contains no reference to Nix’s `libiconv` output, and the complete app passes `codesign --verify --deep --strict`. This includes running the checker on a path containing `/nix/store/` to exercise the header case. The full Nix build could not be rerun in this session because daemon socket access is denied. No hardware was flashed.

**Firmware waiting/progress visibility — October 1, 2026**

Zapp 1.0.2 prints “Firmware loaded” before waiting for bootloader mode, but its `indicatif` spinner and progress bar are hidden when Keyfinder captures a pipe. The bundled helper now emits the physical-reset instruction and actual phase/percentage updates as plain text in that case. Duplicate percentages within a phase are suppressed, and hidden spinners no longer start a steady-tick thread. The Firmware tab also explains when to press reset.

The patched Zapp, app, and DMG build successfully with the pinned Nix toolchain on Apple Silicon. All 24 Rust tests pass, including a subprocess regression that captures the actual progress renderers with `TERM=dumb` and verifies waiting, erasing, writing, resetting, completion, and duplicate suppression. That regression performs no USB enumeration or firmware writes. The app build passes 16 core tests (4,721 assertions) and 10 packaging tests; the packaged app passes all 32 firmware checks. Waiting-state screenshots were rendered and inspected in both themes.

`nix flake check` passes for `aarch64-darwin`. The DMG was mounted read-only, its app copied outside the store, and the copied app passed strict deep signature verification, the Zapp dependency/help guard, and all 106 smoke checks. The image was detached afterward. Reports, build logs, and screenshots are under `artifacts/zapp-progress/`; the rebuilt app and DMG are available through `result-firmware-progress` and `result-firmware-progress-dmg`. No physical keyboard was flashed; hardware acceptance and Intel execution remain unverified.

**Keyboard preview tooltip crash — October 1, 2026**

The crash at 21:24 and an earlier crash at 14:29 both report `EXC_BAD_ACCESS` in `objc_opt_respondsToSelector`, called by `NSToolTipManager displayToolTip:` from its hover timer. `KeyboardView` passed temporary `NSString` bridges to `addToolTip`, whose owner argument is not retained by AppKit. The view now implements `NSViewToolTipOwner` itself and retains text by tooltip tag. Changing preview mode also rebuilds the regions, so disabling previews clears pending tooltip text.

A diagnostic subclass records weak references to the actual owners passed to AppKit, then checks them after an autorelease pool drains. Before the fix, owners were released and seven of the nine new tooltip checks failed. After the fix, all nine pass, along with all earlier checks: 115 smoke checks total in the pinned Swift development build. The checks cover owner lifetime, full tooltip text, layer/model changes, resize, disabling and enabling previews, stale callbacks, clearing a layer, and view release. Reports and a reduced crash summary are under `artifacts/tooltip-crash/`.

The release app and DMG also build successfully. The app build passes 16 core tests (4,721 assertions) and 10 packaging tests, and `nix flake check` passes for `aarch64-darwin`. The DMG was mounted read-only and its app copied to `artifacts/tooltip-crash/standalone/Keyfinder.app`; that copy passes strict deep signature verification, the Zapp dependency/help guard, and all 115 smoke checks. The image was detached after verification. The rebuilt DMG is available through `result-tooltip-fix-dmg`.

**Settings editing shortcuts and text cleanup — October 2, 2026**

⌘C, ⌘V, and the other editing shortcuts did nothing in Settings because Keyfinder installs its own main menu, which had no Edit menu. AppKit routes these key equivalents to text fields through that menu. Keyfinder now adds a standard Edit menu with Undo, Redo, Cut, Copy, Paste, and Select All.

Twelve new smoke checks send real key events through `NSApp.sendEvent` to a Settings text field, with the menu bar icon both hidden and visible. They cover ⌘A, ⌘C, ⌘X, ⌘V, ⌘Z, and ⇧⌘Z, and save and restore the general pasteboard. With the previous `AppDelegate`, all twelve fail. With the fix, all 127 smoke checks pass in a debug `swift build` on Apple Silicon. The 32 firmware checks and 16 core tests (4,721 assertions) also pass.

Settings also no longer shows explanatory captions, the supported-keyboard list, the header subtitle, or the duplicated connection status. Errors, warnings, the bootloader reset prompt, and a reworded Performance note remain. All four pages were rendered and inspected in Light and Dark. The release app and DMG were not rebuilt for this change.

**Preview follows a flashed revision — October 2, 2026**

The live overlay already loaded the revision a keyboard reports after reconnecting. The Settings preview and layout URL followed it only when no URL was saved, so a flash left Settings showing the previous layout. A successful flash now makes the next installed layout replace the preview and URL. A `latest` URL for the same layout is preserved. A failed flash, or an explicit refresh or import before the reconnect, leaves the preview unchanged. Reconnecting without a flash behaves as before.

Five new firmware checks use the simulated Zapp runner and keyboard with cached fixture revisions. Without the change, three fail. With it, all 37 firmware checks, 127 smoke checks, 39 shortcut checks, and 16 core tests (4,721 assertions) pass in a debug `swift build` on Apple Silicon. No keyboard was flashed; reconnection timing and identity reporting on real hardware remain unverified.
