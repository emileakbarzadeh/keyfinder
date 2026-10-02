import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: KeyboardShortcut
    let enabled: Bool
    let onRecord: (KeyboardShortcut) -> Void
    let onRecordingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton { ShortcutRecorderButton() }
    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.shortcut = shortcut; button.onRecord = onRecord; button.onRecordingChanged = onRecordingChanged
        button.isEnabled = enabled
        if !enabled { button.finish() }
        button.refreshTitle()
    }
    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: ()) { button.finish() }
}

final class ShortcutRecorderButton: NSButton {
    var shortcut = KeyboardShortcut.defaultPeek
    var onRecord: ((KeyboardShortcut) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    private(set) var recording = false
    private var windowObserver: NSObjectProtocol?
    override var acceptsFirstResponder: Bool { true }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded; setButtonType(.momentaryPushIn)
        target = self; action = #selector(beginRecording)
        toolTip = "Click, then press a function key or a shortcut with Control, Option, or Command. Esc cancels."
        setAccessibilityLabel("Typing layer shortcut")
        refreshTitle()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func refreshTitle() { if !recording { title = shortcut.title } }
    @objc private func beginRecording() {
        guard !recording, isEnabled else { return }
        recording = true; title = "Press shortcut…"
        onRecordingChanged?(true)
        window?.makeFirstResponder(self)
    }
    override func keyDown(with event: NSEvent) {
        if recording { capture(event) } else { super.keyDown(with: event) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        capture(event); return true
    }
    private func capture(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let candidate = KeyboardShortcut(event: event)
        if candidate.keyCode == 53, candidate.modifiers == 0 { finish(); return }
        guard candidate.isValid else { title = "Use F1–F20 or modifiers"; NSSound.beep(); return }
        shortcut = candidate
        // Save before restoring registration, avoiding a transient old binding.
        onRecord?(candidate)
        finish()
    }
    func finish() {
        guard recording else { return }
        recording = false; refreshTitle(); onRecordingChanged?(false)
    }
    override func resignFirstResponder() -> Bool { finish(); return super.resignFirstResponder() }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        finish()
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
        if let newWindow {
            windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: newWindow, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish() }
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }
    deinit { if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) } }
}
