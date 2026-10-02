# Using Keyfinder

Keyfinder is a macOS 26+ menu bar app for ZSA Moonlander, Voyager, and ErgoDox EZ keyboards. [Download a disk image](../../../releases/latest) or [build and install with Nix](NIX.md), then open the app. Its keyboard icon lives in the menu bar by default; there is no Dock icon.

On first launch, Settings opens with **Keyfinder Demo**, a synthetic three-layer example for typing, symbols, and navigation. The demo belongs to no Oryx account and has no online configuration. Connect a supported keyboard to load its installed revision automatically, paste a layout URL in **Layout & connection**, or import a saved snapshot. The demo cannot be assigned to an unidentified keyboard.

Turn off **Appearance → Show menu bar icon** to hide the icon immediately. The preference persists across launches and does not pause the overlay or USB monitoring. Open Keyfinder from Applications or Spotlight to show Settings again; this also restores a closed or minimized Settings window when the app is already running. Login-item and `--background` startup do not open Settings. You can restore the icon or quit Keyfinder from the Application section in Appearance.

The app identifier is `io.keyfinder.app`. Earlier development builds used a different identifier, so their preferences, login-item registration, and macOS permissions are not reused. Disable an older build's login item before switching, then configure the new app as needed.

## Everyday use

- Layer **0** hides the live overlay. Every other reported layer shows it, including layers added in later revisions.
- **Keyboard** lets you select layers, click keys to inspect tap/hold actions, preview the overlay, and examine inherited keys.
- **Appearance** includes a **Color theme** selector: System (the default), Light, or Dark. System follows macOS automatically; an explicit choice persists across launches. Settings and the overlay use the same theme. This tab also controls size, opacity, key colors, display, position, and optional appearance delay. “Drag overlay into place” temporarily accepts clicks; “Done arranging” restores click-through behavior.
- **Layout & connection** provides Oryx preview refresh, snapshot import/export, connection retry, and pause/resume.
- **Firmware** stages a `.bin` file and runs Zapp when you click **Flash keyboard**.
- **Pause** stops USB monitoring. **Quit** stops the app. The app's own launch-at-login option is off by default. Leave it off if the nix-darwin module manages startup.

While Settings has focus, **⌘W** closes the window and ends any overlay preview while monitoring continues. **⌘Q** quits Keyfinder. Both shortcuts work with the menu bar icon hidden and while editing a text field.

During flashing, ⌘W still closes Settings. Quit asks you to wait for Zapp to finish so it cannot interrupt a firmware write.

The keyboard name in Settings comes from the connected device. Preview labels and key positions come from the preview’s model, which can differ from the connected keyboard. A preview for a different model cannot be assigned to an unidentified device.

The live overlay does not activate the app or take keyboard focus. A current Oryx firmware build reports the initial layer when pairing, including when Keyfinder starts on a secondary layer.

## Hold to show layer 0

Hold **F18** to show the typing layer immediately. Release it to restore the current active layer, or hide the overlay if the keyboard is still on layer 0. Layer changes continue to be tracked while you hold the shortcut. If no keyboard is connected, it shows layer 0 from the saved preview. A connected keyboard always uses its installed layout, even when Settings previews a different model or an unflashed revision.

In **Appearance → Typing layer shortcut**, click the shortcut button and press the replacement. Use a function key on its own, or include Control, Option, or Command. Esc cancels recording. ⌘Q and ⌘W remain reserved for Quit and Close. You can turn the shortcut off without losing the saved binding. Conflicts with another registered shortcut appear in this section; choose another binding or retry after releasing it in the other app.

For a dedicated thumb key, assign a regular **F18** action in Oryx and leave that key transparent on other layers. Keyfinder handles the hold and release. The shortcut applies to any keyboard sending that key and works with the menu bar icon hidden. Disconnecting, pausing, sleeping, leaving the user session, changing the shortcut, or quitting clears a held preview. The shortcut is temporarily unregistered while recording a replacement, paused, or suspended.

## Oryx synchronization

Oryx firmware encodes `layoutID/revisionID` in the USB serial descriptor. Keyfinder reads that identity and loads the **exact installed revision**. Flashing a new layout disconnects and reconnects the keyboard, which triggers synchronization. USB identity selects the keyboard model. Layout URLs and cache entries keep Moonlander, Voyager, and ErgoDox EZ revisions separate, even when their layout and revision IDs match.

An Oryx edit that has not been flashed does not change the live overlay. “Load / refresh preview” retrieves the URL's chosen revision, or the latest revision when the URL contains `latest`. The preview stays separate from the installed layout. Refreshing never flashes firmware, switches keyboard layers, or changes lighting.

Validated snapshots are cached under `~/Library/Application Support/Keyfinder/Layouts`. The synthetic demo remains available as an offline preview. If a newly flashed revision cannot be fetched, Keyfinder displays an unavailable state instead of old key labels. Import/export uses Keyfinder's JSON snapshot format and preserves Oryx action data.

If the firmware cannot identify its layout, you can explicitly choose the preview revision for that connection. The overlay labels this selection as unverified.

## Flash firmware

1. Compile your layout in Oryx and download its firmware.
2. Open **Settings → Firmware**. Drop one `.bin` onto the file target, or use **Choose file…**.
3. Review the filename and connect only the keyboard you intend to update. Click **Flash keyboard** to begin.
4. When **Zapp output** says it is waiting for bootloader mode, press your keyboard’s physical reset button to start flashing. Keep the keyboard connected until Zapp finishes.

Keyfinder copies the selected file into a private temporary directory before displaying it. Changing the download afterward cannot change the bytes being flashed. Empty files, directories, links, and files larger than 64 MiB are rejected. The checksum disclosure shows the staged file’s SHA-256. Zapp handles firmware compatibility and the device write; a `.bin` extension alone does not establish that a file matches your keyboard.

This section accepts `.bin` files. If your keyboard’s firmware download uses another format, such as `.hex`, use Zapp or Keymapp directly. Do not rename its extension.

During flashing, Keyfinder closes its HID connection, unregisters the hold shortcut, hides the overlay, and prevents idle system sleep. Closing Settings leaves the flash running. Quit shows a “Keep flashing” message while Zapp is running; quit again after it exits. There is no cancel button that could interrupt a write. Afterward, monitoring resumes unless it was already paused or your session is asleep/inactive. A reconnect loads the newly installed Oryx revision.

Success requires Zapp to exit successfully. Failures show its output and exit status; correct the reported problem before trying again. Keyfinder runs `zapp flash <staged-file>` directly, without a shell or automatic prompt responses. Only one keyboard should be connected; terminal-only interactions are not supported in this view.

“Firmware loaded” means Zapp has read the file. It still needs the keyboard in bootloader mode before it can write. If an older build shows only that line, press the keyboard’s physical reset button. The bundled Zapp now displays the bootloader waiting message and erasing, writing, and resetting progress in the output panel.

Release apps carry Zapp in the bundle, and the nix-darwin module installs that same app. Source builds find Zapp in the development shell’s `PATH`. No root service or additional macOS privacy request is installed. Staged firmware and output are not saved to preferences or the layout cache.

## Inherited and unknown keys

The stock protocol reports the highest active layer, not the full active-layer set. A transparent key on layer 2 might inherit `1` from layer 0 or `F1` from layer 1. Keyfinder shows `1 / F1` with an inheritance mark when both are possible. Consistent inherited actions are dimmed, and key details list possible lower-layer actions. Disabled keys and unknown actions remain distinct.

Exact resolution of ambiguous stacked layers would require additional firmware reporting. Keyfinder works with stock Oryx firmware and makes this limitation visible. Shortcut labels describe keyboard bindings; application-specific shortcut behavior and OS remappers are outside the app's scope.

## Connection and privacy

Keyfinder opens the vendor-specific raw HID interface non-exclusively. It never seizes the keyboard. Stock firmware also sends physical keydown/up reports while paired; Keyfinder discards them inside the HID callback before allocating a model event or scheduling UI work. It does not record, analyze, or persist typing.

The typing-layer shortcut uses macOS’s registered hotkey API (`RegisterEventHotKey`), which delivers only that shortcut’s press and release events. The recorder receives events in its own Settings window. Neither uses a global keyboard monitor or event tap, and neither needs Accessibility or Input Monitoring access. The app has no privacy usage declarations and does not request Screen Recording, Automation, or Full Disk Access. Launch at login remains an optional system registration.

If macOS denies USB access, the connection panel reports the error. Reconnect the keyboard and retry. After a firmware flash, wait for the keyboard to reconnect. An unavailable-layout error means the installed revision could not be loaded; check connectivity or import a matching snapshot.

Physical USB pairing, live layer reports, permission behavior, and coexistence with Oryx live training/Keymapp still require testing with each physical keyboard model. See the [verification record](VERIFICATION.md) for what has been checked.

## Performance

The app waits on IOKit hotplug/input callbacks and macOS sleep/wake/display notifications. There are no repeating timers, HID polling loops, periodic refreshes, background URL sessions, or animation/render loops. Starting unplugged makes no Oryx request.

The keyboard uses a static AppKit view; hiding it stops drawing. Key labels are prepared when a layout loads, and duplicate layer reports do not update the UI. One-shot connection deadlines and the optional appearance delay are cancelled when no longer needed. Pause tears down the USB monitor entirely.

Zapp starts only for an explicit flash and exits when finished. Firmware file reads and process output run off the main thread; the output log retains at most 32 KiB of backend data. There is no background flasher process or firmware polling while idle.

Real device events, system notifications, UI interaction, layout downloads, and firmware flashing perform work. [Measured idle performance](VERIFICATION.md) describes one observed configuration rather than promising literally zero CPU use.

## Protocol and geometry references

USB protocol and device identity behavior follow ZSA's [Oryx module](https://github.com/zsa/qmk_modules/tree/main/oryx) and [Zapp](https://github.com/zsa/zapp). Moonlander key coordinates and matrix positions follow the [Moonlander definition](https://github.com/zsa/qmk_firmware/blob/93b2b9ec3368f86c5eb5a2e3f934049f8daef885/keyboards/zsa/moonlander/reva/keyboard.json), with thumb-cluster presentation adjusted for the Moonlander shape. See the [architecture](ARCHITECTURE.md) for pinned protocol references.

Voyager and ErgoDox EZ use schematic drawings indexed by Oryx key position. Their matrix coordinates are omitted because Keyfinder does not use physical key reports. These new drawings still need verification with real keyboards.
