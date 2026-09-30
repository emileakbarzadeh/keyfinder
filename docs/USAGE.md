# Using Keyfinder

Keyfinder is a macOS 26+ menu bar app for the ZSA Moonlander. [Download a disk image](../../../releases/latest) or [build and install with Nix](NIX.md), then open the app. Its keyboard icon lives in the menu bar by default; there is no Dock icon.

On first launch, Settings opens with **Keyfinder Demo**, a synthetic three-layer example for typing, symbols, and navigation. The demo belongs to no Oryx account and has no online configuration. Connect a Moonlander to load its installed revision automatically, paste a layout URL in **Layout & connection**, or import a saved snapshot. The demo cannot be assigned to an unidentified keyboard.

Turn off **Appearance → Show menu bar icon** to hide the icon immediately. The preference persists across launches and does not pause the overlay or USB monitoring. Open Keyfinder from Applications or Spotlight to show Settings again; this also restores a closed or minimized Settings window when the app is already running. Login-item and `--background` startup do not open Settings. You can restore the icon or quit Keyfinder from the Application section in Appearance.

The app identifier is `io.keyfinder.app`. Earlier development builds used a different identifier, so their preferences, login-item registration, and macOS permissions are not reused. Disable an older build's login item before switching, then configure the new app as needed.

## Everyday use

- Layer **0** hides the live overlay. Every other reported layer shows it, including layers added in later revisions.
- **Keyboard** lets you select layers, click keys to inspect tap/hold actions, preview the overlay, and examine inherited keys.
- **Appearance** includes a **Color theme** selector: System (the default), Light, or Dark. System follows macOS automatically; an explicit choice persists across launches. Settings and the overlay use the same theme. This tab also controls size, opacity, key colors, display, position, and optional appearance delay. “Drag overlay into place” temporarily accepts clicks; “Done arranging” restores click-through behavior.
- **Layout & connection** provides Oryx preview refresh, snapshot import/export, connection retry, and pause/resume.
- **Pause** stops USB monitoring. **Quit** stops the app. The app's own launch-at-login option is off by default. Leave it off if the nix-darwin module manages startup.

While Settings has focus, **⌘W** closes the window and ends any overlay preview while monitoring continues. **⌘Q** quits Keyfinder. Both shortcuts work with the menu bar icon hidden and while editing a text field.

The live overlay does not activate the app or take keyboard focus. A current Oryx firmware build reports the initial layer when pairing, including when Keyfinder starts on a secondary layer.

## Oryx synchronization

Oryx firmware encodes `layoutID/revisionID` in the USB serial descriptor. Keyfinder reads that identity and loads the **exact installed revision**. Flashing a new layout disconnects and reconnects the keyboard, which triggers synchronization. Both Moonlander revision A and B product IDs are supported by the adapter.

An Oryx edit that has not been flashed does not change the live overlay. “Load / refresh preview” retrieves the URL's chosen revision, or the latest revision when the URL contains `latest`. The preview stays separate from the installed layout. Refreshing never flashes firmware, switches keyboard layers, or changes lighting.

Validated snapshots are cached under `~/Library/Application Support/Keyfinder/Layouts`. The synthetic demo remains available as an offline preview. If a newly flashed revision cannot be fetched, Keyfinder displays an unavailable state instead of old key labels. Import/export uses Keyfinder's JSON snapshot format and preserves Oryx action data.

If the firmware cannot identify its layout, you can explicitly choose the preview revision for that connection. The overlay labels this selection as unverified.

## Inherited and unknown keys

The stock protocol reports the highest active layer, not the full active-layer set. A transparent key on layer 2 might inherit `1` from layer 0 or `F1` from layer 1. Keyfinder shows `1 / F1` with an inheritance mark when both are possible. Consistent inherited actions are dimmed, and key details list possible lower-layer actions. Disabled keys and unknown actions remain distinct.

Exact resolution of ambiguous stacked layers would require additional firmware reporting. Keyfinder works with stock Oryx firmware and makes this limitation visible. Shortcut labels describe keyboard bindings; application-specific shortcut behavior and OS remappers are outside the app's scope.

## Connection and privacy

Keyfinder opens the vendor-specific raw HID interface non-exclusively. It never seizes the keyboard or intercepts normal system keystrokes. Stock firmware also sends physical keydown/up reports while paired; Keyfinder discards them inside the HID callback before allocating a model event or scheduling UI work. It does not record, analyze, or persist typing.

If macOS denies device access, the connection panel explains the error and links to Input Monitoring settings. Grant access if requested, then retry the connection. After a firmware flash, wait for the keyboard to reconnect. An unavailable-layout error means the installed revision could not be loaded; check connectivity or import a matching snapshot.

Physical USB pairing, live layer reports, permission behavior, and coexistence with Oryx live training/Keymapp still require testing with an attached Moonlander. See the [verification record](VERIFICATION.md) for what has been checked.

## Performance

The app waits on IOKit hotplug/input callbacks and macOS sleep/wake/display notifications. There are no repeating timers, HID polling loops, periodic refreshes, background URL sessions, or animation/render loops. Starting unplugged makes no Oryx request.

The keyboard uses a static AppKit view; hiding it stops drawing. Key labels are prepared when a layout loads, and duplicate layer reports do not update the UI. One-shot connection deadlines and the optional appearance delay are cancelled when no longer needed. Pause tears down the USB monitor entirely.

Real device events, system notifications, UI interaction, and layout downloads perform work. [Measured idle performance](VERIFICATION.md) describes one observed configuration rather than promising literally zero CPU use.

## Protocol and geometry references

USB protocol and device identity behavior follow ZSA's [Oryx module](https://github.com/zsa/qmk_modules/tree/main/oryx) and [Zapp](https://github.com/zsa/zapp). Physical key coordinates and matrix positions follow the [Moonlander definition](https://github.com/zsa/qmk_firmware/blob/93b2b9ec3368f86c5eb5a2e3f934049f8daef885/keyboards/zsa/moonlander/reva/keyboard.json), with thumb-cluster presentation adjusted for the Moonlander shape. See the [architecture](ARCHITECTURE.md) for pinned protocol references.
