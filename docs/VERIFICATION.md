# Verification record

Verified September 29, 2026 on macOS 26.6.2, Apple Silicon, using Apple Swift 6.3.3. The Moonlander was intentionally unplugged, as authorized by the user.

**Software checks**

| Check | Result |
| --- | --- |
| Core checks | 13 tests, 1,459 assertions passed |
| Core checks plus explicit live Oryx query | 14 tests, 1,461 assertions passed; retrieved `exampleLayout/exampleRevision` with three 72-key layers |
| Debug AppKit integration | 25 checks passed |
| Packaged release AppKit integration | 25 checks passed |
| Visual inspection | All three keyboard layers and Keyboard, Appearance, and Layout & connection settings pages rendered and reviewed; long legends fitted without dropping layer numbers |
| Standalone packaging | A copied app loaded all resources and rendered three layers while build-tree resources were temporarily unavailable |
| macOS deployment target | `26.0` in both Info.plist and the Mach-O build-version load command |
| Local signature | `codesign --verify --strict` passed; ad-hoc signature |
| App bundle size | 2,308,459 bytes (about 2.20 MiB) |

The integration checks use the actual AppModel, repository, preferences, settings views, and NSPanel. Only the keyboard event source and revision-fetch responses are simulated. They cover:

- Starting unplugged, offline preview, layer-0 hiding, showing secondary layers, and switching labels.
- Preserving the foreground application and current key window, keeping the panel nonactivating, and setting click-through and Spaces/fullscreen collection behavior.
- Cancelling a pending appearance on return to base, disconnect cleanup, explicit preview, and drag-positioning mode.
- No redraw after 1,000 duplicate hidden-layer reports, no network calls for the bundled revision, and stopping/resuming the USB monitor.
- Keeping live labels unchanged after an Oryx preview refresh, activating the matching revision after a simulated flash/reconnect, and reusing its cache.
- Showing no old key labels for an unavailable new revision, preserving the error across layer changes, and rejecting a late response from an earlier connection.
- Preference persistence and preview cleanup.

The executable's `--smoke-test` command returns a nonzero exit code if any check fails. Rendered settings artifacts use AppKit's view rendering and do not require screen recording permission.

**Measured idle performance**

The measurement launched the actual packaged release app with `--background`, kept Settings closed, and left the keyboard disconnected. After a three-second startup allowance, an external Python process sampled the app's macOS process counters. Measurement timers live in that external tool, not in Keyfinder.

| Metric | Observed |
| --- | --- |
| Measurement duration | 30.0027 seconds |
| App CPU time during the interval | 0.000040 seconds |
| Average CPU utilization | 0.000132% of one core |
| Resident memory at end | 46.67 MiB |
| Context switches during interval | 13 |
| Mach messages received during interval | 2 |
| Threads at end | 3 |

These observations establish negligible idle work in this configuration; they are not a promise of literally zero CPU use under every condition. Device events, wake/display notifications, UI interaction, and layout downloads perform necessary work. Stock firmware also sends key-position reports, which are discarded in the HID callback without typing analysis or UI work.

A source audit found no repeating timers, polling loops, background URL sessions, global keyboard event taps, or continuous render/display links in the normal app path. The only scheduled delays are a one-shot connection deadline and an optional one-shot overlay appearance delay. Diagnostic sleeps are confined to explicit test commands.

**Checks requiring the physical setup**

Actual USB pairing and layer reports, permission behavior with the Moonlander attached, real firmware flashing, and coexistence with Oryx live training/Keymapp remain untested because the keyboard is unplugged. Source review and packet fixtures support those paths; they do not substitute for a physical-device test.

Sleep/wake observers, display fallback, fullscreen/Spaces configuration, and launch at login are implemented using native APIs. The tests check the panel configuration and simulated lifecycle rather than rebooting the Mac, changing its display hardware, or changing the user's login-item authorization. Verify those integrations on the user's normal desktop setup when connecting the keyboard.

Developer ID signing/notarization was not performed: the Mac has no valid Developer ID signing identity. The locally generated app is ad-hoc signed and runs locally. Distribution commands are documented in README.md.

**Reproduction and artifact identity**

```sh
scripts/check.sh
swift run KeyfinderCoreChecks --live-oryx
scripts/build-app.sh
dist/Keyfinder.app/Contents/MacOS/Keyfinder --smoke-test artifacts/release-smoke/report.json
python3 scripts/measure-idle.py --seconds 30
codesign --verify --strict dist/Keyfinder.app
```

Generated reports and images are in `artifacts/`. The verified release executable SHA-256 is:

```text
0d67472fb4f80472d9871b8c1df91af05900e5cfdc1e9044871f480ea19d9977
```
