import AppKit
import Carbon
import KeyfinderCore

extension Diagnostics {
    @MainActor static func checkHotKeys(directory: URL) async throws -> [String: Bool] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var checks: [String: Bool] = [:]
        let suite = "io.github.emileakbarzadeh.keyfinder.shortcuts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = Data(#"{"width":1100,"opacity":0.8,"showMenuBarIcon":false}"#.utf8)
        defaults.set(legacy, forKey: "preferences")
        let preferences = Preferences.load(from: defaults)
        checks["old_preferences_gain_f18_without_losing_other_settings"] = preferences.typingLayerHotKey == .defaultPeek
            && preferences.typingLayerHotKeyEnabled && preferences.width == 1100 && !preferences.showMenuBarIcon
        checks["bare_letters_and_standard_quit_close_are_rejected"] = !KeyboardShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: 0).isValid
            && !KeyboardShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(shiftKey)).isValid
            && !KeyboardShortcut(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(cmdKey)).isValid
            && !KeyboardShortcut(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(cmdKey)).isValid
        checks["function_keys_and_modifier_shortcuts_are_supported"] = KeyboardShortcut.defaultPeek.isValid
            && KeyboardShortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey)).isValid
        var invalid = preferences
        invalid.typingLayerHotKey = KeyboardShortcut(keyCode: 500, modifiers: UInt32.max)
        checks["invalid_stored_shortcut_is_disabled"] = !invalid.clamped().typingLayerHotKeyEnabled

        let keyboard = SimulatedKeyboard()
        let hotKey = SimulatedHotKey()
        let geometry = try KeyboardGeometry.load()
        let repository = LayoutRepository(directory: directory, client: OfflineShortcutClient(), bundled: try LayoutSnapshot.bundled())
        let overlay = OverlayController(geometry: geometry)
        let model = AppModel(geometry: geometry, monitor: keyboard, repository: repository, defaults: defaults, overlay: overlay, hotKey: hotKey)
        model.start(observeSleep: false)
        defer { model.stop() }
        checks["shortcut_registers_with_menu_bar_hidden"] = hotKey.registered == .defaultPeek && !model.preferences.showMenuBarIcon
        hotKey.emit(true)
        checks["hold_shows_offline_layer_zero"] = model.isHoldingTypingLayer && overlay.panel.isVisible && overlay.keyboardView.presentedLayer?.position == 0
        hotKey.emit(false)
        checks["release_hides_offline_peek"] = !model.isHoldingTypingLayer && !overlay.panel.isVisible

        keyboard.emit(.connected(ConnectedKeyboard(name: "Moonlander", serial: "keyfinder-demo/v1", productID: 0x1969)))
        keyboard.emit(.layer(0))
        try await shortcutWait { model.installedRevision == "v1" && model.status == "Connected · typing layer" }
        var delayed = model.preferences; delayed.appearanceDelay = 0.5; model.setPreferences(delayed)
        hotKey.emit(true)
        checks["hold_bypasses_appearance_delay_and_passes_clicks_through"] = overlay.panel.isVisible && overlay.panel.ignoresMouseEvents
            && !overlay.panel.canBecomeKey && overlay.keyboardView.presentedLayer?.position == 0
        overlay.keyboardView.displayIfNeeded()
        let draws = overlay.keyboardView.drawCount
        for _ in 0..<10 { hotKey.emit(true) }
        overlay.keyboardView.displayIfNeeded()
        checks["repeated_presses_do_not_redraw"] = overlay.keyboardView.drawCount == draws
        keyboard.emit(.layer(2))
        checks["layer_changes_while_held_keep_typing_layer_visible"] = overlay.keyboardView.presentedLayer?.position == 0 && model.currentLayer == 2
        hotKey.emit(false)
        checks["release_restores_latest_active_layer"] = overlay.keyboardView.presentedLayer?.position == 2 && overlay.panel.isVisible
        keyboard.emit(.layer(0)); hotKey.emit(true); hotKey.emit(false)
        checks["release_on_typing_layer_hides_immediately"] = !overlay.panel.isVisible

        let imported = directory.appendingPathComponent("voyager.json")
        try LayoutRepository.export(keyboardFixture(.voyager), to: imported)
        model.importSnapshot(imported)
        try await shortcutWait { !model.isRefreshing && model.previewSnapshot?.keyboard == .voyager }
        hotKey.emit(true)
        checks["connected_peek_uses_installed_model_not_unflashed_preview"] = overlay.keyboardView.presentedLayer?.keyboard == .moonlander
            && overlay.keyboardView.presentedLayer?.position == 0
        hotKey.emit(false)
        model.showOverlayPreview()
        hotKey.emit(true); hotKey.emit(false)
        checks["release_restores_explicit_preview"] = model.isPreviewingOverlay && overlay.keyboardView.presentedLayer?.keyboard == .voyager
            && overlay.keyboardView.presentedLayer?.position == model.previewLayerIndex
        model.endOverlayPreview()
        hotKey.emit(true); keyboard.emit(.disconnected)
        checks["disconnect_clears_hold"] = !model.isHoldingTypingLayer && !overlay.panel.isVisible
        hotKey.emit(false); hotKey.emit(true)
        checks["new_offline_press_uses_saved_preview"] = overlay.keyboardView.presentedLayer?.keyboard == .voyager && overlay.keyboardView.presentedLayer?.position == 0
        model.togglePause()
        checks["pause_clears_hold_and_unregisters_shortcut"] = !model.isHoldingTypingLayer && !overlay.panel.isVisible && hotKey.registered == nil
        hotKey.emit(true)
        checks["late_press_while_paused_is_ignored"] = !model.isHoldingTypingLayer
        model.togglePause()
        checks["resume_registers_shortcut_without_restoring_hold"] = hotKey.registered == .defaultPeek && !model.isHoldingTypingLayer

        let recorder = ShortcutRecorderButton()
        recorder.onRecordingChanged = model.setHotKeyRecording
        recorder.onRecord = { shortcut in
            var value = model.preferences; value.typingLayerHotKey = shortcut; model.setPreferences(value)
        }
        hotKey.emit(true)
        recorder.performClick(nil)
        checks["recording_unregisters_shortcut_and_clears_hold"] = model.isRecordingHotKey && hotKey.registered == nil && !model.isHoldingTypingLayer
        recorder.keyDown(with: try shortcutEvent(code: UInt16(kVK_ANSI_A)))
        checks["recorder_rejects_bare_letter"] = recorder.recording && model.preferences.typingLayerHotKey == .defaultPeek
        _ = recorder.performKeyEquivalent(with: try shortcutEvent(code: UInt16(kVK_ANSI_K), modifiers: [.control, .option]))
        let custom = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey))
        checks["recorder_saves_and_registers_custom_shortcut"] = !recorder.recording && !model.isRecordingHotKey
            && model.preferences.typingLayerHotKey == custom && hotKey.registered == custom
        checks["custom_shortcut_persists"] = Preferences.load(from: defaults).typingLayerHotKey == custom
        recorder.performClick(nil)
        recorder.keyDown(with: try shortcutEvent(code: UInt16(kVK_Escape)))
        checks["escape_cancels_recording_and_restores_binding"] = !model.isRecordingHotKey && hotKey.registered == custom
        recorder.performClick(nil)
        _ = recorder.resignFirstResponder()
        checks["lost_recorder_focus_restores_binding"] = !model.isRecordingHotKey && hotKey.registered == custom
        hotKey.emit(true)
        var disabled = model.preferences; disabled.typingLayerHotKeyEnabled = false; model.setPreferences(disabled)
        checks["disabling_shortcut_clears_hold_and_persists"] = hotKey.registered == nil && !model.isHoldingTypingLayer && !Preferences.load(from: defaults).typingLayerHotKeyEnabled
        disabled.typingLayerHotKeyEnabled = true; model.setPreferences(disabled)
        hotKey.emit(true); model.setSystemState(sleeping: true)
        checks["sleep_clears_hold_and_unregisters"] = !model.isHoldingTypingLayer && hotKey.registered == nil && !keyboard.running
        model.setSystemState(sessionActive: false); model.setSystemState(sleeping: false)
        checks["wake_keeps_shortcut_suspended_until_session_is_active"] = hotKey.registered == nil && !keyboard.running
        model.setSystemState(sessionActive: true)
        checks["session_return_reregisters_without_stale_hold"] = hotKey.registered == custom && keyboard.running && !model.isHoldingTypingLayer
        hotKey.failRegistration = true; hotKey.stop(); model.updateHotKeyRegistration()
        checks["registration_failure_is_visible_in_settings"] = model.hotKeyError != nil && hotKey.registered == nil
        hotKey.failRegistration = false; model.updateHotKeyRegistration()
        checks["registration_can_be_retried"] = model.hotKeyError == nil && hotKey.registered == custom
        keyboard.emit(.connected(ConnectedKeyboard(name: "Moonlander", serial: "missing/revision", productID: 0x1969)))
        hotKey.emit(true)
        checks["unavailable_installed_layout_never_falls_back_to_preview"] = overlay.keyboardView.presentedLayer == nil && overlay.keyboardView.geometry.keyboard == .moonlander
        model.stop()
        checks["shutdown_unregisters_and_clears_hold"] = hotKey.registered == nil && !model.isHoldingTypingLayer && !overlay.panel.isVisible
        checks.merge(checkNativeHotKey()) { _, new in new }
        return checks
    }

    @MainActor private static func checkNativeHotKey() -> [String: Bool] {
        let hotKey = HoldHotKey()
        let conflicting = HoldHotKey()
        defer { hotKey.stop(); conflicting.stop() }
        var changes: [Bool] = []
        hotKey.onChange = { changes.append($0) }
        let shortcut = KeyboardShortcut(keyCode: UInt32(kVK_F20), modifiers: UInt32(controlKey | optionKey | cmdKey))
        var checks: [String: Bool] = [:]
        do {
            try hotKey.register(shortcut)
            checks["native_hotkey_registration"] = true
            do { try conflicting.register(shortcut); checks["native_shortcut_conflict_is_reported"] = false }
            catch { checks["native_shortcut_conflict_is_reported"] = true }
            sendHotKeyEvent(pressed: true); sendHotKeyEvent(pressed: true); sendHotKeyEvent(pressed: false)
            checks["native_pressed_released_callbacks_ignore_repeats"] = changes == [true, false]
            changes = []
            sendHotKeyEvent(pressed: true); hotKey.resetHeldState(); sendHotKeyEvent(pressed: true)
            sendHotKeyEvent(pressed: false); sendHotKeyEvent(pressed: true); sendHotKeyEvent(pressed: false)
            checks["native_reset_ignores_repeat_until_release"] = changes == [true, false, true, false]
            hotKey.stop(); changes = []
            try hotKey.register(shortcut)
            sendHotKeyEvent(pressed: true, id: 1)
            checks["stale_registration_events_are_ignored"] = changes.isEmpty
            sendHotKeyEvent(pressed: true, id: 2); hotKey.stop()
            checks["native_stop_releases_held_shortcut"] = changes == [true, false]
        } catch {
            checks["native_hotkey_registration"] = false
            print("Native shortcut registration failed: \(error.localizedDescription)")
        }
        return checks
    }

    // These events stay inside this process; they do not inject system keystrokes.
    @MainActor private static func sendHotKeyEvent(pressed: Bool, id: UInt32 = 1) {
        var event: EventRef?
        guard CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(pressed ? kEventHotKeyPressed : kEventHotKeyReleased),
                          GetCurrentEventTime(), EventAttributes(kEventAttributeUserEvent), &event) == noErr, let event else { return }
        defer { ReleaseEvent(event) }
        var hotKeyID = EventHotKeyID(signature: 0x4B46504B, id: id)
        guard SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &hotKeyID) == noErr else { return }
        SendEventToEventTarget(event, GetApplicationEventTarget())
    }
    @MainActor private static func shortcutEvent(code: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                          windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code) else {
            throw KeyfinderError.service("Could not create a recorder event.")
        }
        return event
    }
    @MainActor private static func shortcutWait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw KeyfinderError.service("Shortcut check timed out.")
    }
}

@MainActor private final class SimulatedHotKey: HoldHotKeyMonitoring {
    var onChange: ((Bool) -> Void)?
    var registered: KeyboardShortcut?
    var failRegistration = false
    func register(_ shortcut: KeyboardShortcut) throws {
        if failRegistration { throw KeyfinderError.service("Shortcut is already in use.") }
        registered = shortcut
    }
    func stop() { registered = nil; onChange?(false) }
    func resetHeldState() { onChange?(false) }
    func emit(_ held: Bool) { onChange?(held) }
}

private struct OfflineShortcutClient: LayoutFetching {
    func fetch(keyboard: KeyboardModel, layoutID: String, revisionID: String) async throws -> LayoutSnapshot {
        throw KeyfinderError.service("Offline shortcut fixture: missing layout")
    }
}
