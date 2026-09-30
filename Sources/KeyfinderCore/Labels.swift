import Foundation

public enum KeyAppearance: String, Sendable { case normal, layer, inherited, ambiguous, disabled, unknown }

public struct PresentedKey: Equatable, Sendable {
    public let label: String
    public let secondary: String
    public let detail: String
    public let appearance: KeyAppearance
    public let color: String?
    public init(label: String, secondary: String = "", detail: String, appearance: KeyAppearance = .normal, color: String? = nil) {
        self.label = label; self.secondary = secondary; self.detail = detail; self.appearance = appearance; self.color = color
    }
}

public struct PresentedLayer: Equatable, Sendable {
    public let position: Int
    public let name: String
    public let layoutTitle: String
    public let revision: String
    public let keys: [PresentedKey]
    public var inheritedCount: Int { keys.filter { $0.appearance == .inherited || $0.appearance == .ambiguous }.count }
    public var ambiguousCount: Int { keys.filter { $0.appearance == .ambiguous }.count }
}

public enum LabelResolver {
    public static func prepare(_ snapshot: LayoutSnapshot) -> [Int: PresentedLayer] {
        let layers = snapshot.layers
        // With default-layer switching in a layout, the stock protocol cannot prove the base.
        let changesDefault = layers.contains { layer in layer.keys.contains { key in
            KeyDefinition.gestures.contains { ["DF", "PDF", "QK_DEF_LAYER"].contains(key.action($0)?["code"]?.string ?? "") }
        } }
        return Dictionary(uniqueKeysWithValues: layers.map { layer in
            let keys = layer.keys.enumerated().map { index, key -> PresentedKey in
                guard key.isTransparent else { return direct(key) }
                let candidates = layers.filter { $0.position < layer.position }.compactMap { candidate -> (Int, PresentedKey)? in
                    let lower = candidate.keys[index]
                    return lower.isTransparent ? nil : (candidate.position, direct(lower))
                }
                guard !changesDefault, let first = candidates.first else {
                    return PresentedKey(label: "↳", secondary: "inherited", detail: "Inherits from an active lower layer. The keyboard does not report the complete active layer set.", appearance: .ambiguous)
                }
                // Compare meaning, not just the visible/custom label: two identically named macros may differ.
                let meanings = layers.filter { $0.position < layer.position && !$0.keys[index].isTransparent }.map { semanticKey($0.keys[index]) }
                if meanings.allSatisfy({ $0 == meanings.first }) {
                    return PresentedKey(label: first.1.label, secondary: first.1.secondary,
                        detail: "Inherited from a lower layer.\n\n" + first.1.detail, appearance: .inherited, color: key.color)
                }
                var labels: [String] = []
                for (_, candidate) in candidates where !labels.contains(candidate.label) { labels.append(candidate.label) }
                let short = labels.count <= 2 && labels.joined(separator: " / ").count <= 14 ? labels.joined(separator: " / ") : "↳"
                let details = candidates.map { "Layer \($0.0): \($0.1.detail)" }.joined(separator: "\n\n")
                return PresentedKey(label: short, secondary: "inherited", detail: "Depends on which lower layers are active.\n\n" + details, appearance: .ambiguous, color: key.color)
            }
            return (layer.position, PresentedLayer(position: layer.position, name: layer.displayName, layoutTitle: snapshot.title, revision: snapshot.revisionID, keys: keys))
        })
    }

    private static func semanticKey(_ key: KeyDefinition) -> [JSONValue] {
        key.semanticActions.map { action in
            guard var object = action.object else { return action }
            for cosmetic in ["color", "description"] { object.removeValue(forKey: cosmetic) }
            // Missing optional metadata and explicit null have the same meaning.
            object = object.filter { !$0.value.isNull }
            return .object(object)
        }
    }

    public static func direct(_ key: KeyDefinition) -> PresentedKey {
        let actions = KeyDefinition.gestures.compactMap { gesture -> (String, String)? in
            key.action(gesture).map { (gesture, actionLabel($0)) }
        }
        guard !actions.isEmpty else {
            return PresentedKey(label: "?", secondary: "unknown", detail: "Unsupported key data\n\n" + key.raw.prettyPrinted, appearance: .unknown)
        }
        let first = actions.first!
        let title = key.customLabel ?? key.raw["emoji"]?.string?.nonEmpty ?? first.1
        let gestureNames = ["tap": "Tap", "hold": "Hold", "doubleTap": "Double tap", "tapHold": "Tap, then hold"]
        var secondary = ""
        if actions.count > 1 {
            secondary = actions.dropFirst().map { (gestureNames[$0.0] ?? $0.0) + ": " + $0.1 }.joined(separator: " · ")
        } else if key.customLabel != nil && title != first.1 { secondary = first.1 }
        let codes = KeyDefinition.gestures.compactMap { key.action($0)?["code"]?.string }
        let disabled = !codes.isEmpty && codes.allSatisfy { ["KC_NO", "KC_NONE", "XXXXXXX"].contains($0) }
        let unknown = actions.contains { $0.1.hasPrefix("?") }
        let switchesLayer = KeyDefinition.gestures.contains { key.action($0)?["layer"]?.integer != nil }
        var detail = actions.map { (gestureNames[$0.0] ?? $0.0) + ": " + $0.1 }.joined(separator: "\n")
        if let custom = key.customLabel { detail = custom + "\n\n" + detail }
        for gesture in KeyDefinition.gestures {
            if let macro = key.action(gesture)?["macro"], !macro.isNull { detail += "\n\nMacro (\(gesture)):\n" + macro.prettyPrinted }
        }
        if unknown { detail += "\n\n" + key.raw.prettyPrinted }
        return PresentedKey(label: disabled ? "—" : title, secondary: secondary, detail: detail,
                            appearance: disabled ? .disabled : (unknown ? .unknown : (switchesLayer ? .layer : .normal)), color: key.color)
    }

    public static func actionLabel(_ action: JSONValue) -> String {
        guard let object = action.object else { return "? action" }
        if let macro = object["macro"], !macro.isNull {
            return object["description"]?.string?.nonEmpty ?? macro["name"]?.string?.nonEmpty ?? "Macro"
        }
        guard let code = object["code"]?.string else { return "? action" }
        let layerNames = ["MO": "Layer", "LT": "Layer", "TG": "Toggle", "TO": "Go to", "TT": "Tap toggle", "OSL": "Once", "DF": "Default", "PDF": "Default"]
        if let target = object["layer"]?.integer, let name = layerNames[code] { return "\(name) \(target)" }
        if code == "OSM" { return "Once " + modifierLabel(object["modifier"]?.string ?? "modifier") }
        let modifiers = object["modifiers"]
        var prefix = ""
        for (left, right, symbol) in [("leftCtrl", "rightCtrl", "⌃"), ("leftAlt", "rightAlt", "⌥"), ("leftShift", "rightShift", "⇧"), ("leftGui", "rightGui", "⌘")] {
            if modifiers?[left]?.boolean == true || modifiers?[right]?.boolean == true { prefix += symbol }
        }
        return prefix + codeLabel(code)
    }

    private static func modifierLabel(_ value: String) -> String {
        let upper = value.uppercased()
        if upper.contains("CTL") || upper.contains("CTRL") { return "⌃" }
        if upper.contains("SFT") || upper.contains("SHIFT") { return "⇧" }
        if upper.contains("ALT") { return "⌥" }
        if upper.contains("GUI") { return "⌘" }
        return codeLabel(value)
    }

    public static func codeLabel(_ code: String) -> String {
        if code.hasPrefix("KC_") {
            let suffix = String(code.dropFirst(3))
            if suffix.count == 1, suffix.first?.isLetter == true || suffix.first?.isNumber == true { return suffix }
            if suffix.hasPrefix("F"), let n = Int(suffix.dropFirst()), (1...24).contains(n) { return suffix }
        }
        return labels[code] ?? "? " + code
    }

    private static let labels: [String: String] = {
        var result: [String: String] = [:]
        func add(_ label: String, _ codes: String) { for code in codes.split(separator: " ") { result[String(code)] = label } }
        add("—", "KC_NO KC_NONE XXXXXXX"); add("↳", "KC_TRANSPARENT KC_TRNS _______")
        add("Esc", "KC_ESCAPE KC_ESC"); add("Tab", "KC_TAB"); add("Space", "KC_SPACE KC_SPC")
        add("↵", "KC_ENTER KC_ENT"); add("⌫", "KC_BSPC KC_BACKSPACE KC_BSPACE"); add("⌦", "KC_DELETE KC_DEL")
        add("←", "KC_LEFT"); add("→", "KC_RIGHT KC_RGHT"); add("↑", "KC_UP"); add("↓", "KC_DOWN")
        add("⌘", "KC_LEFT_GUI KC_RIGHT_GUI KC_LGUI KC_RGUI"); add("⌥", "KC_LEFT_ALT KC_RIGHT_ALT KC_LALT KC_RALT")
        add("⌃", "KC_LEFT_CTRL KC_RIGHT_CTRL KC_LCTL KC_RCTL"); add("⇧", "KC_LEFT_SHIFT KC_RIGHT_SHIFT KC_LSFT KC_RSFT")
        add("Hyper", "ALL_T KC_HYPR HYPR"); add("Meh", "MEH_T KC_MEH MEH")
        add("Caps", "KC_CAPS KC_CAPSLOCK KC_CAPS_LOCK"); add("Caps word", "CW_TOGG QK_CAPS_WORD_TOGGLE")
        add("Home", "KC_HOME"); add("End", "KC_END"); add("Pg ↑", "KC_PGUP KC_PAGE_UP"); add("Pg ↓", "KC_PGDN KC_PGDOWN KC_PAGE_DOWN")
        add("Insert", "KC_INSERT KC_INS"); add("Print", "KC_PSCR KC_PSCREEN KC_PRINT_SCREEN")
        add("Scr lock", "KC_SCROLL_LOCK KC_SCRL"); add("Pause", "KC_PAUSE KC_PAUS"); add("Menu", "KC_APP KC_APPLICATION")
        add("-", "KC_MINUS KC_MINS"); add("=", "KC_EQUAL KC_EQL"); add("[", "KC_LBRC KC_LBRACKET KC_LEFT_BRACKET")
        add("]", "KC_RBRC KC_RBRACKET KC_RIGHT_BRACKET"); add("\\", "KC_BSLS KC_BSLASH KC_BACKSLASH KC_NUBS KC_NONUS_BACKSLASH")
        add(";", "KC_SCLN KC_SCOLON KC_SEMICOLON"); add("'", "KC_QUOTE KC_QUOT"); add("`", "KC_GRAVE KC_GRV")
        add(",", "KC_COMMA KC_COMM"); add(".", "KC_DOT"); add("/", "KC_SLASH KC_SLSH")
        add("!", "KC_EXLM KC_EXCLAIM"); add("@", "KC_AT"); add("#", "KC_HASH KC_NUHS KC_NONUS_HASH")
        add("$", "KC_DLR KC_DOLLAR"); add("%", "KC_PERC KC_PERCENT"); add("^", "KC_CIRC KC_CIRCUMFLEX")
        add("&", "KC_AMPR KC_AMPERSAND"); add("*", "KC_ASTR KC_ASTERISK"); add("(", "KC_LPRN KC_LEFT_PAREN")
        add(")", "KC_RPRN KC_RIGHT_PAREN"); add("_", "KC_UNDS KC_UNDERSCORE"); add("+", "KC_PLUS")
        add("{", "KC_LCBR KC_LEFT_CURLY_BRACE"); add("}", "KC_RCBR KC_RIGHT_CURLY_BRACE"); add("|", "KC_PIPE")
        add(":", "KC_COLN KC_COLON"); add("\"", "KC_DQUO KC_DQT KC_DOUBLE_QUOTE")
        add("<", "KC_LABK KC_LT KC_LEFT_ANGLE_BRACKET"); add(">", "KC_RABK KC_GT KC_RIGHT_ANGLE_BRACKET")
        add("?", "KC_QUES KC_QUESTION"); add("~", "KC_TILD KC_TILDE")
        for n in 0...9 { add("\(n)", "KC_KP_\(n) KC_P\(n)") }
        add("Num lock", "KC_NUM KC_NUM_LOCK KC_NUMLOCK"); add("÷", "KC_KP_SLASH KC_PSLS"); add("×", "KC_KP_ASTERISK KC_PAST")
        add("+", "KC_KP_PLUS KC_PPLS"); add("−", "KC_KP_MINUS KC_PMNS"); add("↵", "KC_KP_ENTER KC_PENT")
        add(".", "KC_KP_DOT KC_PDOT"); add("=", "KC_KP_EQUAL KC_PEQL"); add(",", "KC_KP_COMMA KC_PCMM")
        add("Play / pause", "KC_MEDIA_PLAY_PAUSE KC_MPLY"); add("Previous", "KC_MEDIA_PREV_TRACK KC_MPRV")
        add("Next", "KC_MEDIA_NEXT_TRACK KC_MNXT"); add("Stop", "KC_MEDIA_STOP KC_MSTP")
        add("Vol +", "KC_AUDIO_VOL_UP KC_VOLU"); add("Vol −", "KC_AUDIO_VOL_DOWN KC_VOLD"); add("Mute", "KC_AUDIO_MUTE KC_MUTE")
        add("Back", "KC_WWW_BACK KC_WBAK"); add("Forward", "KC_WWW_FORWARD KC_WFWD"); add("Refresh", "KC_WWW_REFRESH KC_WREF")
        add("Mouse ↑", "KC_MS_UP KC_MS_U"); add("Mouse ↓", "KC_MS_DOWN KC_MS_D")
        add("Mouse ←", "KC_MS_LEFT KC_MS_L"); add("Mouse →", "KC_MS_RIGHT KC_MS_R")
        add("Scroll ↑", "KC_MS_WH_UP KC_WH_U"); add("Scroll ↓", "KC_MS_WH_DOWN KC_WH_D")
        add("Scroll ←", "KC_MS_WH_LEFT KC_WH_L"); add("Scroll →", "KC_MS_WH_RIGHT KC_WH_R")
        for n in 1...8 { add("Mouse \(n)", "KC_MS_BTN\(n) KC_BTN\(n)") }
        for n in 0...2 { add("Speed \(n + 1)", "KC_MS_ACCEL\(n) KC_ACL\(n)") }
        add("Color", "RGB"); add("RGB on/off", "RGB_TOG RGB_TOGGLE")
        add("Effect +", "RGB_MOD RGB_MODE_FORWARD"); add("Effect −", "RGB_RMOD RGB_MODE_REVERSE")
        add("Light +", "RGB_VAI"); add("Light −", "RGB_VAD"); add("Hue +", "RGB_HUI"); add("Hue −", "RGB_HUD")
        add("Sat +", "RGB_SAI"); add("Sat −", "RGB_SAD"); add("Solid", "RGB_SLD RGB_MODE_PLAIN")
        add("Layer color", "TOGGLE_LAYER_COLOR"); add("Audio", "AU_TOGG AU_TOG"); add("Music", "MU_TOGG MU_TOG")
        add("Next tune", "MU_NEXT MU_MOD"); add("Auto shift", "AS_TOGG AS_TOG")
        add("Bootloader", "QK_BOOT RESET"); add("Reboot", "QK_REBOOT"); add("Clear EEPROM", "EE_CLR QK_CLEAR_EEPROM")
        add("Sleep", "KC_SYSTEM_SLEEP KC_SLEP"); add("Wake", "KC_SYSTEM_WAKE KC_WAKE"); add("Power", "KC_SYSTEM_POWER KC_PWR")
        return result
    }()
}
