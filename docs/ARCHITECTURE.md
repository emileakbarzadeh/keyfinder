# Architecture

Keyfinder is a native macOS 26+ overlay for one connected ZSA Moonlander. It shows the keyboard's highest active layer, hides on layer 0, and loads the exact Oryx revision installed on the device. The Swift core is independent of the desktop adapter to leave room for a future Linux port.

## Components

| Component | Responsibility |
| --- | --- |
| `KeyfinderCore` | Validate layouts and device identities, decode Oryx reports, resolve key labels, and cache revision snapshots. |
| `HIDMonitor` | Discover Moonlander revisions A and B, pair through the raw HID interface, and deliver device events on the main run loop. |
| `AppModel` | Coordinate connection state, exact-revision retrieval, preview selection, and persisted preferences. |
| `OverlayController` / `KeyboardView` | Present a nonactivating, click-through AppKit panel using the 72-key Moonlander geometry. |
| `AppDelegate` / `SettingsView` | Manage the optional menu bar icon, Settings, explicit reopening, and login behavior. |
| Nix expressions | Pin the compiler and SDK; build, check, sign, and package the app; configure the nix-darwin LaunchAgent. |

## Device events and revision identity

The app opens ZSA's raw HID interface without seizing the keyboard. It subscribes to device and input callbacks, requests the current firmware/layer state during pairing, and discards physical keypress reports. It does not collect typing history or install a global keyboard event tap.

Oryx firmware exposes a `layoutID/revisionID` identity. The live overlay uses that exact revision, not whichever revision is newest online. Each connection has a generation-scoped request lease; replies from an earlier connection cannot replace the active layout.

| Event | Result |
| --- | --- |
| Connect or wake | Pair, establish the current layer, and load the installed revision. |
| Layer 0 report | Cancel any delayed appearance and hide immediately. |
| Higher layer report | Present cached labels for that layer, or an explicit loading/error state. |
| Preview refresh | Fetch the selected Oryx revision for inspection; leave live labels tied to the installed identity. |
| Flash and reconnect | Read the new identity and activate its matching revision. |
| Disconnect, pause, or sleep | Cancel pending work and hide the live overlay. |

An unavailable revision never falls back to another layout's labels. Cached snapshots work offline. When firmware cannot identify its layout, a user may explicitly associate a real preview revision; the overlay marks that association as unverified.

## Offline demo and first connection

`Resources/DemoLayout.json` is a synthetic fixture with three layers and 72 positions per layer. Its `keyfinder-demo/v1` identity is local example data, not a published Oryx layout. The app does not offer an Oryx link or permit an unverified keyboard association for this demo.

New preferences contain no preset Oryx URL. The first successfully retrieved installed layout initializes the preview and URL when no URL has been selected. A pasted URL or imported snapshot remains an explicit preview choice. The demo also supplies repeatable test and screenshot data without exposing a contributor's keyboard configuration.

## Transparent keys

Stock Oryx reports the highest active layer, not the complete set of active lower layers. A transparent key can therefore have more than one effective action. For example, the demo has `1` on layer 0, `F1` on layer 1, and transparency at the same position on layer 2. The overlay displays `1 / F1` rather than guessing whether layer 1 is active.

The resolver compares action semantics, including tap/hold gestures and macros. Cosmetic labels do not establish equivalence. Disabled, inherited, ambiguous, and unknown actions remain distinct. Raw source JSON is retained for lossless import/export and future action formats.

## Window lifecycle and performance

The overlay cannot become the key or main window and passes clicks through. Dragging is enabled only during an explicit arrangement preview. It joins desktop Spaces and fullscreen environments; a missing display falls back to the main display.

The menu bar icon is optional. Opening the app while the icon is hidden reveals Settings, including restoring a closed or minimized window. Login-item and `--background` launches remain quiet. Pause stops USB monitoring; Quit terminates the app without a keep-alive loop.

There are no polling loops, repeating timers, scheduled Oryx refreshes, or continuous render callbacks. Labels are prepared when a layout changes. Duplicate layer reports do no UI work, and hidden overlays do no drawing. Connection deadlines and optional appearance delays are cancellable one-shot tasks. Diagnostic timing lives only in explicitly invoked verification tools.

## Validation and future work

The [verification record](VERIFICATION.md) distinguishes core tests, simulated AppKit integration, packaging checks, measured performance, and physical hardware acceptance. Contributions should preserve those distinctions.

Future work includes physical acceptance across Moonlander revisions, Linux desktop integration, configurable hidden layers, and optional firmware support for full active/default-layer bitmasks. Linux packaging and exact resolution of ambiguous stacked layers are not currently implemented.

## Protocol references

- [ZSA Oryx module](https://github.com/zsa/qmk_modules/tree/main/oryx): pairing, layer updates, and raw HID reports.
- [ZSA device identifiers](https://github.com/zsa/zapp/blob/a1be75837323001ad1ae8e5787d88cd33f2ccc46/zapp-core/src/device/ids.rs): Moonlander revisions A and B.
- [ZSA installed-layout detection](https://github.com/zsa/zapp/blob/a1be75837323001ad1ae8e5787d88cd33f2ccc46/zapp/src/main.rs): firmware identity parsing.
- [Moonlander geometry](https://github.com/zsa/qmk_firmware/blob/93b2b9ec3368f86c5eb5a2e3f934049f8daef885/keyboards/zsa/moonlander/reva/keyboard.json): physical key positions.
- [Oryx with custom QMK](https://github.com/zsa/oryx-with-custom-qmk): a possible path for additional firmware state reporting.
