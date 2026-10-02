import Foundation

/// Oryx model identifiers are kept separate from USB names and interface labels.
public enum KeyboardModel: String, Codable, CaseIterable, Sendable {
    case moonlander, voyager
    case ergodoxEZ = "ergodox-ez"

    public var displayName: String {
        switch self {
        case .moonlander: "Moonlander"
        case .voyager: "Voyager"
        case .ergodoxEZ: "ErgoDox EZ"
        }
    }
    public var keyCount: Int {
        switch self {
        case .moonlander: 72
        case .voyager: 52
        case .ergodoxEZ: 76
        }
    }
    public var resourceName: String {
        switch self {
        case .moonlander: "Moonlander"
        case .voyager: "Voyager"
        case .ergodoxEZ: "ErgoDoxEZ"
        }
    }
    public static func detect(productID: Int, productName: String = "") -> KeyboardModel? {
        switch productID {
        case 0x1969, 0x1972: return .moonlander
        case 0x1977: return .voyager
        case 0x4974, 0x4976: return .ergodoxEZ
        default: break
        }
        // New hardware revisions may keep the product name but change USB IDs.
        let name = productName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch name {
        case "moonlander", "zsa moonlander", "moonlander mark i": return .moonlander
        case "voyager", "zsa voyager": return .voyager
        case "ergodox ez", "ergodox ez glow", "ergodox ez shine": return .ergodoxEZ
        default: return nil
        }
    }
}
