import AppKit
import SwiftUI
import KeyfinderCore

/// Explicit command-line verification only. Normal app startup never runs these tasks.
@MainActor enum Diagnostics {
    private(set) static var smokePassed = false
    static func renderPreviews(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let geometry = try MoonlanderGeometry.load()
        let layers = LabelResolver.prepare(try LayoutSnapshot.bundled())
        for mode in [AppAppearance.dark, .light] {
            let suffix = mode == .light ? "-light" : ""
            for index in layers.keys.sorted() {
                let view = KeyboardView(geometry: geometry)
                view.appearance = mode.appKit
                view.preview = true; view.presentedLayer = layers[index]
                view.frame = NSRect(x: 0, y: 0, width: 1100, height: KeyboardView.height(forWidth: 1100))
                try capture(view, to: directory.appendingPathComponent("layer-\(index)\(suffix).png"))
            }
            let neutral = KeyboardView(geometry: geometry)
            neutral.appearance = mode.appKit
            neutral.presentedLayer = layers[1]; neutral.useKeyColors = false
            neutral.unverified = true; neutral.selectedIndex = 1
            neutral.frame = NSRect(x: 0, y: 0, width: 1100, height: KeyboardView.height(forWidth: 1100))
            try capture(neutral, to: directory.appendingPathComponent("unverified-without-key-colors\(suffix).png"))
        }
        print("Rendered \(layers.count) layers in light and dark mode to \(directory.path)")
    }

    static func capture(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw KeyfinderError.service("Could not allocate preview image.") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw KeyfinderError.service("Could not render preview image.") }
        try png.write(to: url, options: .atomic)
    }

    static func renderIcon(to url: URL) throws {
        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        image.lockFocus()
        let background = NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 202, yRadius: 202)
        NSGradient(starting: Theme.dark.key, ending: Theme.ink)?.draw(in: background, angle: -60)
        for row in 0..<3 {
            for col in 0..<3 {
                let selected = row == 1 && col == 1
                let rect = NSRect(x: 210 + col * 205, y: 210 + row * 205, width: 178, height: 178)
                let key = NSBezierPath(roundedRect: rect, xRadius: 36, yRadius: 36)
                (selected ? Theme.orange : row == 2 && col == 2 ? Theme.red : Theme.parchment).setFill(); key.fill()
                Theme.parchment.withAlphaComponent(0.24).setStroke(); key.lineWidth = 3; key.stroke()
                if selected {
                    let mark = NSBezierPath(); mark.move(to: NSPoint(x: rect.minX + 49, y: rect.minY + 92)); mark.line(to: NSPoint(x: rect.minX + 80, y: rect.minY + 62)); mark.line(to: NSPoint(x: rect.minX + 133, y: rect.minY + 118))
                    Theme.ink.setStroke(); mark.lineWidth = 15; mark.lineCapStyle = .round; mark.lineJoinStyle = .round; mark.stroke()
                }
            }
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { throw KeyfinderError.service("Could not render app icon.") }
        try png.write(to: url, options: .atomic)
    }

    static func runSmokeTest(reportURL: URL) {
        Task { @MainActor in
            var checks: [String: Bool] = [:]
            var failure: String?
            var model: AppModel?
            var focusWindow: NSWindow?
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Keyfinder-smoke-\(UUID().uuidString)")
            let suiteName = "io.keyfinder.smoke.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defer {
                model?.stop(); focusWindow?.close()
                defaults.removePersistentDomain(forName: suiteName)
                try? FileManager.default.removeItem(at: temporary)
                NSApp.stop(nil)
                if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
            }
            do {
                try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let geometry = try MoonlanderGeometry.load()
                let snapshot = try LayoutSnapshot.bundled()
                let monitor = SimulatedKeyboard()
                let client = ScenarioClient()
                let repository = LayoutRepository(directory: temporary, client: client, bundled: snapshot)
                let overlay = OverlayController(geometry: geometry)
                let appModel = AppModel(geometry: geometry, monitor: monitor, repository: repository, defaults: defaults, overlay: overlay)
                model = appModel
                appModel.start(observeSleep: false)
                checks["starts_without_keyboard"] = !appModel.connected && !overlay.panel.isVisible
                checks["offline_preview_has_72_keys"] = appModel.previewLayers[1]?.keys.count == 72
                checks["first_launch_has_no_preset_oryx_profile"] = appModel.preferences.layoutURL.isEmpty && appModel.previewSnapshot?.isDemo == true && appModel.previewOryxURL == nil
                monitor.emit(.connected(ConnectedKeyboard(name: "Moonlander", serial: "", productID: 0x1969)))
                appModel.usePreviewForUnidentifiedKeyboard()
                checks["demo_cannot_be_assigned_to_an_unknown_keyboard"] = appModel.installedRevision == nil
                monitor.emit(.disconnected)

                let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1000, height: 820), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = NSHostingView(rootView: SettingsView(model: appModel))
                focusWindow = window
                NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
                for mode in [AppAppearance.dark, .light] {
                    var preferences = appModel.preferences; preferences.appearance = mode
                    appModel.setPreferences(preferences)
                    let suffix = mode == .light ? "-light" : ""
                    for page in SettingsPage.allCases {
                        window.contentView = NSHostingView(rootView: SettingsView(model: appModel, initialPage: page))
                        try await Task.sleep(for: .milliseconds(150))
                        let name = page == .keyboard ? "settings" : page == .appearance ? "settings-appearance" : "settings-connection"
                        if let view = window.contentView { try capture(view, to: reportURL.deletingLastPathComponent().appendingPathComponent("\(name)\(suffix).png")) }
                    }
                }
                var automatic = appModel.preferences; automatic.appearance = .system
                appModel.setPreferences(automatic)
                window.makeKeyAndOrderFront(nil)
                let previousKeyWindow = NSApp.keyWindow
                let foregroundBeforeOverlay = NSWorkspace.shared.frontmostApplication?.processIdentifier
                checks["focus_test_has_foreground_application"] = foregroundBeforeOverlay != nil

                monitor.emit(.connected(ConnectedKeyboard(name: "Moonlander", serial: "keyfinder-demo/v1", productID: 0x1969)))
                monitor.emit(.layer(0))
                try await Task.sleep(for: .milliseconds(100))
                checks["typing_layer_hidden"] = !overlay.panel.isVisible
                monitor.emit(.layer(1))
                try await Task.sleep(for: .milliseconds(75))
                checks["secondary_layer_visible"] = overlay.panel.isVisible && overlay.keyboardView.presentedLayer?.position == 1
                checks["overlay_cannot_steal_focus"] = !overlay.panel.canBecomeKey && !overlay.panel.canBecomeMain && NSApp.keyWindow === previousKeyWindow
                    && NSWorkspace.shared.frontmostApplication?.processIdentifier == foregroundBeforeOverlay
                checks["overlay_click_through"] = overlay.panel.ignoresMouseEvents
                checks["overlay_joins_spaces"] = overlay.panel.collectionBehavior.contains(.canJoinAllSpaces) && overlay.panel.collectionBehavior.contains(.fullScreenAuxiliary)
                monitor.emit(.layer(2))
                checks["layer_change_updates_labels"] = overlay.keyboardView.presentedLayer?.keys[1].label == "1 / F1"
                monitor.emit(.layer(0))
                try await Task.sleep(for: .milliseconds(75))
                let hiddenDrawCount = overlay.keyboardView.drawCount
                for _ in 0..<1000 { monitor.emit(.layer(0)) }
                try await Task.sleep(for: .milliseconds(250))
                checks["hidden_duplicate_events_do_not_redraw"] = hiddenDrawCount == overlay.keyboardView.drawCount && !overlay.panel.isVisible

                var preferences = appModel.preferences; preferences.appearanceDelay = 0.2
                appModel.setPreferences(preferences)
                monitor.emit(.layer(1)); monitor.emit(.layer(0))
                try await Task.sleep(for: .milliseconds(260))
                checks["return_to_base_cancels_delayed_appearance"] = !overlay.panel.isVisible
                preferences.appearanceDelay = 0; appModel.setPreferences(preferences)
                monitor.emit(.layer(1)); monitor.emit(.disconnected)
                checks["disconnect_hides_overlay"] = !overlay.panel.isVisible
                appModel.showOverlayPreview()
                checks["explicit_preview_works_unplugged"] = overlay.panel.isVisible
                appModel.endOverlayPreview()
                appModel.togglePause()
                checks["pause_stops_usb_monitoring"] = !monitor.running && !overlay.panel.isVisible
                appModel.togglePause()
                checks["resume_restarts_usb_monitoring"] = monitor.running && appModel.status == "Waiting for your Moonlander"
                let requests = await client.requests
                checks["no_network_for_bundled_layout_or_idle"] = requests.isEmpty
                checks["preference_round_trip"] = Preferences.load(from: defaults) == appModel.preferences
                appModel.showOverlayPreview(arrange: true)
                checks["arrange_mode_allows_dragging"] = !overlay.panel.ignoresMouseEvents
                appModel.endOverlayPreview()
                checks["preview_cleanup_hides_panel"] = !overlay.panel.isVisible

                // Exercise actual AppModel/repository integration, not just the pure reducer.
                let updated = try revision(of: snapshot, id: "testUpdated", replacementCode: "KC_F24")
                await client.allow(updated)
                monitor.emit(.connected(ConnectedKeyboard(name: "Moonlander", serial: "keyfinder-demo/v1", productID: 0x1969)))
                monitor.emit(.layer(1))
                try await waitUntil { overlay.keyboardView.presentedLayer?.revision == snapshot.revisionID }
                appModel.refreshLayout(url: "https://configure.zsa.io/moonlander/layouts/\(snapshot.layoutID)/latest/0")
                try await waitUntil { !appModel.isRefreshing }
                checks["preview_refresh_does_not_change_installed_labels"] = appModel.previewSnapshot?.revisionID == updated.revisionID && overlay.keyboardView.presentedLayer?.keys[1].label == "F1"
                monitor.emit(.disconnected)
                monitor.emit(.connected(ConnectedKeyboard(name: "Moonlander", serial: "keyfinder-demo/testUpdated", productID: 0x1972)))
                monitor.emit(.layer(1))
                try await waitUntil { overlay.keyboardView.presentedLayer?.revision == updated.revisionID }
                checks["flash_reconnect_activates_matching_revision"] = overlay.keyboardView.presentedLayer?.keys[1].label == "F24"
                let afterFlash = await client.requests
                checks["prefetched_revision_avoids_second_request"] = afterFlash == ["latest"]

                monitor.emit(.disconnected)
                monitor.emit(.connected(ConnectedKeyboard(name: "Moonlander", serial: "keyfinder-demo/missingRevision", productID: 0x1969)))
                monitor.emit(.layer(1))
                try await waitUntil { appModel.status == "Layout unavailable" }
                checks["uncached_offline_revision_never_shows_old_labels"] = overlay.panel.isVisible && overlay.keyboardView.presentedLayer == nil
                monitor.emit(.layer(2))
                checks["failed_layout_stays_unavailable_across_layer_changes"] = appModel.status == "Layout unavailable" && overlay.keyboardView.message?.contains("could not be loaded") == true

                let delayed = try revision(of: snapshot, id: "testDelayed", replacementCode: "KC_F23")
                await client.block(delayed)
                monitor.emit(.disconnected)
                monitor.emit(.connected(ConnectedKeyboard(name: "Moonlander", serial: "keyfinder-demo/testDelayed", productID: 0x1969)))
                monitor.emit(.layer(1))
                try await waitUntil { await client.hasPendingRequest }
                monitor.emit(.disconnected)
                monitor.emit(.connected(ConnectedKeyboard(name: "Moonlander", serial: "keyfinder-demo/v1", productID: 0x1969)))
                monitor.emit(.layer(1))
                try await waitUntil { overlay.keyboardView.presentedLayer?.revision == snapshot.revisionID }
                await client.release()
                try await Task.sleep(for: .milliseconds(75))
                checks["late_response_cannot_overwrite_reconnected_layout"] = overlay.keyboardView.presentedLayer?.keys[1].label == "F1" && appModel.installedRevision == snapshot.revisionID
                monitor.emit(.disconnected)
                var freshPreferences = appModel.preferences; freshPreferences.layoutURL = ""
                appModel.setPreferences(freshPreferences)
                let demoFile = temporary.appendingPathComponent("demo.json")
                try LayoutRepository.export(snapshot, to: demoFile)
                appModel.importSnapshot(demoFile)
                try await waitUntil { !appModel.isRefreshing && appModel.previewSnapshot?.isDemo == true }
                monitor.emit(.connected(ConnectedKeyboard(name: "Moonlander", serial: "\(updated.layoutID)/\(updated.revisionID)", productID: 0x1969)))
                try await waitUntil { appModel.previewSnapshot?.identity == updated.identity && appModel.preferences.layoutURL == updated.identity.url.absoluteString }
                checks["first_identified_layout_populates_preview_and_oryx_url"] = appModel.previewOryxURL == updated.identity.url
                monitor.emit(.disconnected)
                checks.merge(try await checkApplicationLifecycle(geometry: geometry, snapshot: snapshot, directory: temporary)) { _, new in new }
            } catch { failure = error.localizedDescription }
            let passed = failure == nil && checks.values.allSatisfy { $0 }
            smokePassed = passed
            let report: [String: Any] = ["passed": passed, "checks": checks, "error": failure as Any? ?? NSNull(), "hardware_tested": false]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: reportURL, options: .atomic) }
            print(passed ? "Smoke test passed (\(checks.count) checks)." : "Smoke test FAILED. See \(reportURL.path)")
            if !passed { fputs("Keyfinder smoke verification failed.\n", stderr) }
        }
    }

    private static func checkApplicationLifecycle(geometry: [KeyGeometry], snapshot: LayoutSnapshot, directory: URL) async throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        let suiteName = "io.keyfinder.lifecycle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let originalAppearance = NSApp.appearance
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            NSApp.appearance = originalAppearance
        }

        var original = Preferences()
        original.width = 1170; original.opacity = 0.72; original.useKeyColors = false
        original.layoutURL = "https://configure.zsa.io/moonlander/layouts/keyfinder-demo/v1/0"
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        legacy.removeValue(forKey: "showMenuBarIcon")
        legacy.removeValue(forKey: "appearance")
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: "preferences")
        defaults.set(true, forKey: "hasLaunched")
        checks["existing_preferences_survive_new_appearance_and_icon_settings"] = Preferences.load(from: defaults) == original

        legacy["appearance"] = "future-theme"
        let unknownTheme = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: legacy))
        checks["unknown_theme_falls_back_without_resetting_preferences"] = unknownTheme == original

        func launch(background: Bool = false) -> (AppDelegate, AppModel, SimulatedKeyboard) {
            let monitor = SimulatedKeyboard()
            let model = AppModel(geometry: geometry, monitor: monitor,
                                 repository: LayoutRepository(directory: directory, client: ScenarioClient(), bundled: snapshot),
                                 defaults: defaults, overlay: OverlayController(geometry: geometry))
            let delegate = AppDelegate(backgroundLaunch: background, defaults: defaults, model: model)
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            return (delegate, model, monitor)
        }
        let termination = Notification(name: NSApplication.willTerminateNotification)
        do {
            let (delegate, model, monitor) = launch()
            defer { delegate.applicationWillTerminate(termination) }
            checks["menu_bar_icon_visible_by_default"] = delegate.statusItem?.isVisible == true
            var hidden = model.preferences; hidden.showMenuBarIcon = false
            model.setPreferences(hidden)
            model.showOverlayPreview()
            checks["hiding_icon_keeps_monitor_and_overlay_active"] = delegate.statusItem?.isVisible == false && monitor.running && model.overlay.panel.isVisible
            checks["hidden_icon_preference_persists"] = !Preferences.load(from: defaults).showMenuBarIcon

            delegate.openSettings()
            func hasAppearance(_ name: NSAppearance.Name) -> Bool {
                let views = [delegate.settingsWindow?.contentView, model.overlay.keyboardView]
                return views.allSatisfy { $0?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == name }
            }
            for mode in [AppAppearance.dark, .light] {
                // An explicit choice must override the opposite inherited appearance.
                NSApp.appearance = (mode == .dark ? AppAppearance.light : .dark).appKit
                var preference = model.preferences; preference.appearance = mode
                model.setPreferences(preference)
                let expected: NSAppearance.Name = mode == .dark ? .darkAqua : .aqua
                try await waitUntil { hasAppearance(expected) }
                checks["\(mode.rawValue)_mode_updates_settings_and_visible_overlay"] = model.overlay.panel.isVisible
                    && model.overlay.keyboardView.presentedLayer?.position == model.previewLayerIndex
                    && delegate.settingsWindow?.appearance?.name == expected
                checks["\(mode.rawValue)_appearance_preference_persists"] = Preferences.load(from: defaults).appearance == mode
            }
            var automatic = model.preferences; automatic.appearance = .system
            model.setPreferences(automatic)
            for mode in [AppAppearance.light, .dark] {
                let drawCount = model.overlay.keyboardView.drawCount
                NSApp.appearance = mode.appKit
                let expected: NSAppearance.Name = mode == .dark ? .darkAqua : .aqua
                try await waitUntil { hasAppearance(expected) && model.overlay.keyboardView.drawCount > drawCount }
                checks["system_\(mode.rawValue)_appearance_redraws_visible_overlay"] = model.overlay.panel.appearance == nil
                    && delegate.settingsWindow?.appearance == nil
            }
            model.endOverlayPreview()
            try await Task.sleep(for: .milliseconds(100))
            let hiddenDraws = model.overlay.keyboardView.drawCount
            NSApp.appearance = AppAppearance.light.appKit
            try await Task.sleep(for: .milliseconds(150))
            checks["system_theme_change_keeps_hidden_overlay_idle"] = !model.overlay.panel.isVisible && model.overlay.keyboardView.drawCount == hiddenDraws
            model.showOverlayPreview()
            try await waitUntil { model.overlay.keyboardView.drawCount > hiddenDraws }
            checks["overlay_shows_current_theme_after_hidden_appearance_change"] = hasAppearance(.aqua) && model.overlay.panel.isVisible
            model.endOverlayPreview()
            var light = model.preferences; light.appearance = .light
            model.setPreferences(light)
            checks.merge(try await checkStandardShortcuts(delegate: delegate, model: model, monitor: monitor, iconVisible: false)) { _, new in new }
        }
        do {
            let (delegate, model, monitor) = launch()
            defer { delegate.applicationWillTerminate(termination) }
            checks["saved_appearance_applies_when_settings_reopens"] = model.preferences.appearance == .light && delegate.settingsWindow?.appearance?.name == .aqua
            checks["direct_launch_with_hidden_icon_opens_settings"] = delegate.statusItem?.isVisible == false && delegate.settingsWindow?.isVisible == true
            delegate.settingsWindow?.close()
            _ = delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            checks["reopening_hidden_app_restores_closed_settings"] = delegate.settingsWindow?.isVisible == true
            delegate.settingsWindow?.miniaturize(nil)
            try await waitUntil { delegate.settingsWindow?.isMiniaturized == true }
            _ = delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            try await waitUntil { delegate.settingsWindow?.isMiniaturized == false && delegate.settingsWindow?.isVisible == true }
            checks["reopening_hidden_app_restores_minimized_settings"] = true
            var shown = model.preferences; shown.showMenuBarIcon = true
            model.setPreferences(shown)
            checks["menu_bar_icon_can_be_restored_immediately"] = delegate.statusItem?.isVisible == true && Preferences.load(from: defaults).showMenuBarIcon
            checks.merge(try await checkStandardShortcuts(delegate: delegate, model: model, monitor: monitor, iconVisible: true)) { _, new in new }
        }
        var hidden = Preferences.load(from: defaults); hidden.showMenuBarIcon = false
        hidden.save(to: defaults); defaults.removeObject(forKey: "hasLaunched")
        do {
            let (delegate, _, monitor) = launch(background: true)
            defer { delegate.applicationWillTerminate(termination) }
            checks["hidden_background_launch_stays_quiet"] = delegate.settingsWindow == nil && delegate.statusItem?.isVisible == false && monitor.running
            _ = delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            checks["background_app_opens_settings_on_explicit_reopen"] = delegate.settingsWindow?.isVisible == true
        }
        return checks
    }

    private static func checkStandardShortcuts(delegate: AppDelegate, model: AppModel, monitor: SimulatedKeyboard, iconVisible: Bool) async throws -> [String: Bool] {
        delegate.openSettings()
        guard let window = delegate.settingsWindow else { throw KeyfinderError.service("Settings did not open for shortcut verification.") }
        // Exercise AppKit event dispatch with a field editor as first responder.
        let field = NSTextField(frame: NSRect(x: 20, y: 20, width: 240, height: 24))
        window.contentView?.addSubview(field)
        defer { field.removeFromSuperview() }
        window.makeFirstResponder(field)
        try await waitUntil { NSApp.keyWindow === window && window.firstResponder is NSTextView }
        let suffix = iconVisible ? "visible_icon" : "hidden_icon"
        var checks: [String: Bool] = [:]
        func press(_ character: String, keyCode: UInt16) throws {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command],
                                              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                              context: nil, characters: character, charactersIgnoringModifiers: character,
                                              isARepeat: false, keyCode: keyCode) else {
                throw KeyfinderError.service("Could not create a shortcut event.")
            }
            NSApp.sendEvent(event)
        }
        model.showOverlayPreview()
        try press("w", keyCode: 13)
        checks["command_w_closes_settings_with_\(suffix)"] = !window.isVisible
        checks["command_w_cleans_up_preview_and_keeps_monitoring_with_\(suffix)"] = !model.isPreviewingOverlay && !model.overlay.panel.isVisible && monitor.running

        delegate.openSettings()
        window.makeFirstResponder(field)
        try await waitUntil { NSApp.keyWindow === window && window.firstResponder is NSTextView }
        // Cancel termination only in this test so the smoke runner can finish.
        let probe = TerminationProbe()
        let previousDelegate = NSApp.delegate
        NSApp.delegate = probe
        defer { NSApp.delegate = previousDelegate }
        try press("q", keyCode: 12)
        checks["command_q_requests_termination_with_\(suffix)"] = probe.requested
        return checks
    }

    private static func waitUntil(_ condition: () async -> Bool) async throws {
        // Bounded synchronization inside this explicit diagnostic command only.
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw KeyfinderError.service("A smoke-test state transition timed out.")
    }

    private static func revision(of snapshot: LayoutSnapshot, id: String, replacementCode: String) throws -> LayoutSnapshot {
        var source = snapshot.source.object!
        var layers = source["layers"]!.array!
        var layer = layers[1].object!
        var keys = layer["keys"]!.array!
        keys[1] = .object(["tap": .object(["code": .string(replacementCode)])])
        layer["keys"] = .array(keys); layers[1] = .object(layer)
        source["hashId"] = .string(id); source["layers"] = .array(layers)
        return try LayoutSnapshot(layoutID: snapshot.layoutID, title: snapshot.title, revisionID: id, source: .object(source)).validated()
    }
}

@MainActor private final class TerminationProbe: NSObject, NSApplicationDelegate {
    private(set) var requested = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        requested = true
        return .terminateCancel
    }
}

@MainActor final class SimulatedKeyboard: KeyboardMonitoring {
    var onEvent: ((KeyboardEvent) -> Void)?
    private(set) var running = false
    func start() { running = true }
    func stop() { running = false; onEvent?(.disconnected) }
    func reconnect() { stop(); start() }
    func emit(_ event: KeyboardEvent) { onEvent?(event) }
}

private actor ScenarioClient: LayoutFetching {
    var requests: [String] = []
    private var latest: LayoutSnapshot?
    private var blocked: LayoutSnapshot?
    private var continuation: CheckedContinuation<LayoutSnapshot, Error>?
    var hasPendingRequest: Bool { continuation != nil }
    func allow(_ snapshot: LayoutSnapshot) { latest = snapshot }
    func block(_ snapshot: LayoutSnapshot) { blocked = snapshot }
    func release() {
        if let blocked { continuation?.resume(returning: blocked) }
        continuation = nil; blocked = nil
    }
    func fetch(layoutID: String, revisionID: String) async throws -> LayoutSnapshot {
        requests.append(revisionID)
        if revisionID == blocked?.revisionID {
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        if let latest, revisionID == "latest" || revisionID == latest.revisionID { return latest }
        throw KeyfinderError.service("Offline test: this revision is not cached.")
    }
}
