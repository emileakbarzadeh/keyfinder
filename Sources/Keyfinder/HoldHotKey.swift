import AppKit
import Carbon

struct KeyboardShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    static let defaultPeek = KeyboardShortcut(keyCode: UInt32(kVK_F18), modifiers: 0)
    static let modifierMask = UInt32(cmdKey | optionKey | controlKey | shiftKey)
    private static let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                                       kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]

    var isValid: Bool {
        guard keyCode < 128, ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode), modifiers & ~Self.modifierMask == 0 else { return false }
        if modifiers == UInt32(cmdKey), [UInt32(kVK_ANSI_Q), UInt32(kVK_ANSI_W)].contains(keyCode) { return false }
        return Self.functionKeys.contains(Int(keyCode)) || modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
    }
    init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode); modifiers = 0
        for (flag, bit) in [(NSEvent.ModifierFlags.command, cmdKey), (.option, optionKey), (.control, controlKey), (.shift, shiftKey)] {
            if event.modifierFlags.contains(flag) { modifiers |= UInt32(bit) }
        }
    }
    var title: String {
        var prefix = ""
        for (bit, symbol) in [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")] {
            if modifiers & UInt32(bit) != 0 { prefix += symbol }
        }
        if let index = Self.functionKeys.firstIndex(of: Int(keyCode)) { return prefix + "F\(index + 1)" }
        let special = [kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Escape: "Esc", kVK_Delete: "Delete",
                       kVK_ForwardDelete: "Forward Delete", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
                       kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down"]
        return prefix + (special[Int(keyCode)] ?? translatedKey ?? "Key \(keyCode)")
    }
    private var translatedKey: String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKey: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let result = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKey, characters.count, &length, &characters)
        guard result == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}

@MainActor protocol HoldHotKeyMonitoring: AnyObject {
    var onChange: ((Bool) -> Void)? { get set }
    func register(_ shortcut: KeyboardShortcut) throws
    func stop()
    func resetHeldState()
}

/// Registers one shortcut with the OS. It does not monitor the keyboard event stream.
@MainActor final class HoldHotKey: HoldHotKeyMonitoring {
    var onChange: ((Bool) -> Void)?
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var shortcut: KeyboardShortcut?
    private var registrationID: UInt32 = 0
    private var held = false
    private var suppressedUntilRelease = false
    private static let signature: OSType = 0x4B46504B // KFPK

    func register(_ shortcut: KeyboardShortcut) throws {
        if reference != nil, self.shortcut == shortcut { return }
        stop()
        guard shortcut.isValid else { throw HotKeyError.invalid }
        var events = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                      EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                Unmanaged<HoldHotKey>.fromOpaque(context).takeUnretainedValue().receive(event)
            }
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else { stop(); throw HotKeyError.registration(result) }
        registrationID &+= 1
        let id = EventHotKeyID(signature: Self.signature, id: registrationID)
        let registration = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
        guard registration == noErr else { stop(); throw HotKeyError.registration(registration) }
        self.shortcut = shortcut
    }
    private func receive(_ event: EventRef) -> OSStatus {
        var id = EventHotKeyID()
        guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
              reference != nil, id.signature == Self.signature, id.id == registrationID else { return OSStatus(eventNotHandledErr) }
        let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
        if !pressed { suppressedUntilRelease = false }
        guard !suppressedUntilRelease, held != pressed else { return noErr }
        held = pressed; onChange?(pressed)
        return noErr
    }
    func resetHeldState() {
        if held { held = false; suppressedUntilRelease = true; onChange?(false) }
    }
    func stop() {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        reference = nil; handler = nil; shortcut = nil
        let wasHeld = held
        held = false; suppressedUntilRelease = false
        if wasHeld { onChange?(false) }
    }
    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}

private enum HotKeyError: LocalizedError {
    case invalid, registration(OSStatus)
    var errorDescription: String? {
        switch self {
        case .invalid: "Use a function key or a shortcut with Control, Option, or Command. ⌘Q and ⌘W stay available for Quit and Close."
        case .registration(let status) where status == eventHotKeyExistsErr: "This shortcut is already in use. Record a different shortcut."
        case .registration(let status): "macOS could not register this shortcut (\(status)). Choose another shortcut or try again."
        }
    }
}
