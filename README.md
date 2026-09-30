# Keyfinder

Keyfinder is a native macOS 26+ menu bar app for your ZSA Moonlander. It displays the keyboard when you enter any layer above 0, updates as you change layers, and hides when you return to typing. The overlay passes clicks through and does not take keyboard focus.

Your [example Oryx layout](https://configure.zsa.io/moonlander/layouts/exampleLayout/latest/0), revision `exampleRevision`, is bundled so you can explore its three layers before plugging in the keyboard.

**Build and open**

Use the Swift 6 toolchain from Apple's Command Line Tools or Xcode on macOS 26 or later. No package downloads or third-party runtime libraries are required.

```sh
scripts/build-app.sh
open dist/Keyfinder.app
```

The script produces `dist/Keyfinder.app` and `dist/Keyfinder-macOS.zip`. It builds for the host architecture with release optimization and signs the app locally. You can move the app into Applications. Its keyboard icon lives in the menu bar; it does not have a Dock icon.

On first launch, Settings opens with the offline keyboard preview. Select a layer and click individual keys to inspect their actions. Connect the Moonlander when ready. A current Oryx firmware build reports the initial layer immediately, including when the app starts on a secondary layer.

**Using the app**

- Layer 0 hides the live overlay. Every other reported layer shows it, including layers added in later revisions.
- Settings → Keyboard lets you inspect tap/hold actions, show an overlay preview, and examine inherited keys.
- Settings → Appearance controls size, opacity, key colors, display, position, and optional appearance delay. “Drag overlay into place” temporarily accepts clicks for positioning; “Done arranging” restores normal behavior.
- Settings → Layout & connection provides Oryx preview refresh, snapshot import/export, connection retry, and pause/resume.
- Pause stops the USB monitor. Quit stops the app. Launch at login is optional and disabled by default.

When macOS denies access to the keyboard, the connection panel explains the error and links to Input Monitoring settings. Retry after granting access if needed. Keyfinder uses the vendor-specific HID interface and never seizes the keyboard or intercepts normal system keystrokes.

**How synchronization works**

Oryx firmware encodes `layoutID/revisionID` in the USB serial descriptor. Keyfinder reads that identity and loads the exact installed revision. Flashing a new layout disconnects and reconnects the keyboard, which triggers automatic sync. The app supports both Moonlander revision A and B product IDs.

An Oryx edit that has not been flashed does not change the live overlay. “Load / refresh preview” retrieves the URL's chosen revision, or the latest one when the URL contains `latest`. The preview is separate from the installed layout. Refreshing never flashes firmware, switches keyboard layers, or changes lighting.

Validated snapshots are cached under `~/Library/Application Support/Keyfinder/Layouts`. The bundled revision also acts as an offline cache. A newly flashed revision that cannot be fetched displays an unavailable state instead of old key labels. Import/export uses Keyfinder's JSON snapshot format and preserves Oryx action data. If the firmware cannot identify its layout, you can explicitly choose the preview revision for that connection; the overlay labels this selection as unverified.

**Performance behavior**

There are no repeating timers, HID polling loops, periodic refreshes, background URL sessions, or animation/render loops. The app waits on IOKit hotplug/input callbacks and macOS sleep/wake/display notifications. It fetches a layout only on an uncached installed revision or an explicit refresh. Starting with the keyboard unplugged makes no Oryx request.

Ordinary layer reports update the UI only when the layer changes. The keyboard is drawn with a static AppKit view; hiding it stops drawing. Key labels are prepared when a layout loads. One-shot connection deadlines and an optional appearance delay are cancelled when no longer needed. Pause tears down the USB monitor entirely.

Stock Oryx firmware also sends physical keydown/up reports while paired. The HID callback discards those before allocating a model event or scheduling UI work. It does not record, analyze, or persist typing. A resident app necessarily performs a little work in response to real device/system events; it does not run a continuous background job. See [verification results](docs/VERIFICATION.md) for measured idle CPU use and the scope of testing.

**Inherited keys**

The stock protocol reports the highest active layer, not the full active-layer set. For example, your layer-2 `1` key can inherit `1` from layer 0 or `F1` from layer 1. Keyfinder shows `1 / F1` with an inheritance mark rather than guessing. Consistent inherited actions are dimmed; details list possible lower-layer actions. Disabled keys and unknown actions remain distinct.

Exact resolution of ambiguous stacked layers would require additional firmware reporting. The app works with stock Oryx firmware and makes this limitation visible. Shortcut labels describe keyboard bindings; application-specific shortcut behavior and OS remappers are outside the app's scope.

**Verification commands**

```sh
scripts/check.sh
scripts/build-app.sh
python3 scripts/measure-idle.py --seconds 30
```

The checks include a standalone Swift core runner, rendered previews, and an AppKit smoke test with simulated USB events. The runner avoids a dependency on XCTest/Swift Testing, which are absent from some Command Line Tools installations. Failures return a nonzero exit code. The smoke test creates temporary windows and isolated settings, then cleans them up. It never modifies or flashes a keyboard.

Artifacts are written to `artifacts/`: layer images, settings screenshots, a smoke-test JSON report, and idle-performance measurements. These generated files and `dist/` are excluded from Git.

Other useful commands:

```sh
swift run KeyfinderCoreChecks
swift run KeyfinderCoreChecks --live-oryx
dist/Keyfinder.app/Contents/MacOS/Keyfinder --diagnostics
dist/Keyfinder.app/Contents/MacOS/Keyfinder --background
```

`--live-oryx` adds an explicit network check against the supplied layout. `--background` suppresses the first-launch settings window. Normal menu bar controls remain available.

**Project structure**

| Path | Purpose |
| --- | --- |
| `Sources/KeyfinderCore` | Layout models, action labels, geometry, protocol decoding, cache, and revision-state rules |
| `Sources/Keyfinder` | IOKit adapter, menu bar app, SwiftUI settings, AppKit overlay, and explicit diagnostic commands |
| `Tests/KeyfinderCoreTests` | Dependency-free core checks |
| `Packaging` | App bundle metadata; minimum OS is 26.0 |
| `scripts` | Build, verification, and external performance measurement |
| `PLAN.md` | Product specification and protocol research |

The core does not import AppKit, SwiftUI, or IOKit. Linux remains a possible future port with its own device and desktop integration; X11/Wayland overlay behavior requires separate validation.

**Signing for distribution**

The default build is ad-hoc signed for local use. Developer ID signing and Apple notarization require your signing identity and notary credentials; neither is needed to build and run locally, and neither is fabricated by the build script.

```sh
KEYFINDER_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' scripts/build-app.sh
xcrun notarytool submit dist/Keyfinder-macOS.zip --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple dist/Keyfinder.app
ditto -c -k --keepParent dist/Keyfinder.app dist/Keyfinder-macOS.zip
```

**Sources**

USB protocol and device identity behavior were checked against ZSA's [Oryx module](https://github.com/zsa/qmk_modules/tree/main/oryx) and [Zapp](https://github.com/zsa/zapp). Physical key coordinates and matrix positions follow the [Moonlander definition](https://github.com/zsa/qmk_firmware/blob/93b2b9ec3368f86c5eb5a2e3f934049f8daef885/keyboards/zsa/moonlander/reva/keyboard.json), with thumb-cluster presentation adjusted for the Moonlander shape. The bundled layout comes from the user-supplied Oryx revision. See `PLAN.md` for pinned research references.
