import Foundation

public enum KeyfinderError: LocalizedError, Equatable {
    case invalidURL, invalidIdentity, invalidLayout(String), service(String)
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Use a supported keyboard layout URL from configure.zsa.io."
        case .invalidIdentity: return "The keyboard did not provide a recognizable Oryx layout and revision."
        case .invalidLayout(let detail): return "This layout cannot be used: \(detail)"
        case .service(let detail): return detail
        }
    }
}

public struct LayoutIdentity: Codable, Hashable, Sendable {
    public let layoutID: String
    public let revisionID: String
    public let keyboard: KeyboardModel
    public var cacheKey: String { "\(keyboard.rawValue)-\(layoutID)-\(revisionID)-v1" }
    public var url: URL { URL(string: "https://configure.zsa.io/\(keyboard.rawValue)/layouts/\(layoutID)/\(revisionID)/0")! }

    public init(layoutID: String, revisionID: String, keyboard: KeyboardModel = .moonlander) throws {
        guard Self.validID(layoutID), Self.validID(revisionID), revisionID != "latest" else { throw KeyfinderError.invalidIdentity }
        self.layoutID = layoutID; self.revisionID = revisionID; self.keyboard = keyboard
    }
    public init(serial: String, keyboard: KeyboardModel = .moonlander) throws {
        let parts = serial.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { throw KeyfinderError.invalidIdentity }
        try self.init(layoutID: String(parts[0]), revisionID: String(parts[1]), keyboard: keyboard)
    }
    private enum CodingKeys: String, CodingKey { case layoutID, revisionID, keyboard }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(layoutID: values.decode(String.self, forKey: .layoutID),
                      revisionID: values.decode(String.self, forKey: .revisionID),
                      keyboard: values.decodeIfPresent(KeyboardModel.self, forKey: .keyboard) ?? .moonlander)
    }
    public static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }
}

public struct OryxLocation: Equatable, Sendable {
    public let keyboard: KeyboardModel
    public let layoutID: String
    public let revisionID: String?
    public init(url text: String) throws {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host?.lowercased() == "configure.zsa.io",
              url.user == nil, url.password == nil, url.port == nil else { throw KeyfinderError.invalidURL }
        let parts = url.path.split(separator: "/").map(String.init)
        guard (3...5).contains(parts.count), let keyboard = KeyboardModel(rawValue: parts[0]), parts[1] == "layouts",
              LayoutIdentity.validID(parts[2]) else { throw KeyfinderError.invalidURL }
        if parts.count == 5, Int(parts[4]) == nil { throw KeyfinderError.invalidURL }
        self.keyboard = keyboard
        layoutID = parts[2]
        let revision = parts.count >= 4 ? parts[3] : "latest"
        guard LayoutIdentity.validID(revision) else { throw KeyfinderError.invalidURL }
        revisionID = revision == "latest" ? nil : revision
    }
}

public struct KeyDefinition: Codable, Equatable, Sendable {
    public let raw: JSONValue
    public init(_ raw: JSONValue) { self.raw = raw }
    public static let gestures = ["tap", "hold", "doubleTap", "tapHold"]
    public func action(_ gesture: String) -> JSONValue? {
        if let action = raw[gesture], !action.isNull { return action }
        // A few older Oryx exports store a plain key action directly.
        if gesture == "tap", raw["code"]?.string != nil { return raw }
        return nil
    }
    public var customLabel: String? { raw["customLabel"]?.string?.nonEmpty }
    public var color: String? { raw["glowColor"]?.string ?? action("tap")?["color"]?.string }
    public var isTransparent: Bool {
        guard let object = raw.object else { return false }
        let actions = Self.gestures.compactMap(action)
        if !actions.isEmpty {
            return actions.allSatisfy { ["KC_TRANSPARENT", "KC_TRNS", "_______"].contains($0["code"]?.string ?? "") }
        }
        // Known modern Oryx null action slots compile to KC_TRANSPARENT.
        // A wholly unrecognized object does not silently become a transparent key.
        return object.keys.contains("tap") && Self.gestures.allSatisfy { object[$0] == nil || object[$0] == .null }
            && !object.keys.contains(where: { $0.lowercased().contains("action") && object[$0] != .null })
    }
    public var semanticActions: [JSONValue] { Self.gestures.map { action($0) ?? .null } }
}

public struct KeyboardLayer: Codable, Equatable, Sendable {
    public let position: Int
    public let title: String
    public let keys: [KeyDefinition]
    public init(position: Int, title: String, keys: [KeyDefinition]) { self.position = position; self.title = title; self.keys = keys }
    public var displayName: String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.lowercased() == "layer" || name.lowercased() == "layer \(position)" { return "Layer \(position)" }
        return "\(name) · \(position)"
    }
}

/// Source JSON is retained so export/import is lossless across future action types.
public struct LayoutSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let layoutID: String
    public let keyboard: KeyboardModel
    public var geometry: String { keyboard.rawValue }
    public let title: String
    public let revisionID: String
    public let source: JSONValue

    public var keyboardName: String { keyboard.displayName }
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, layoutID, title, revisionID, source
        case keyboard = "geometry"
    }

    public init(layoutID: String, title: String, revisionID: String, source: JSONValue, keyboard: KeyboardModel = .moonlander) {
        self.schemaVersion = 1; self.layoutID = layoutID; self.keyboard = keyboard
        self.title = title; self.revisionID = revisionID; self.source = source
    }
    public var identity: LayoutIdentity { try! LayoutIdentity(layoutID: layoutID, revisionID: revisionID, keyboard: keyboard) }
    public var isDemo: Bool { keyboard == .moonlander && layoutID == "keyfinder-demo" && revisionID == "v1" }
    public var layers: [KeyboardLayer] {
        (source["layers"]?.array ?? []).compactMap { raw in
            guard let position = raw["position"]?.integer, let keys = raw["keys"]?.array else { return nil }
            return KeyboardLayer(position: position, title: raw["title"]?.string ?? "", keys: keys.map(KeyDefinition.init))
        }.sorted { $0.position < $1.position }
    }
    public func validated(expected: LayoutIdentity? = nil) throws -> LayoutSnapshot {
        guard schemaVersion == 1 else { throw KeyfinderError.invalidLayout("unsupported file version or keyboard model.") }
        let identity = try LayoutIdentity(layoutID: layoutID, revisionID: revisionID, keyboard: keyboard)
        if let expected, expected != identity { throw KeyfinderError.invalidLayout("the returned revision does not match the installed firmware.") }
        guard source["hashId"]?.string == revisionID, let entries = source["layers"]?.array, !entries.isEmpty, entries.count <= 32 else {
            throw KeyfinderError.invalidLayout("missing revision or layer data.")
        }
        let layers = self.layers
        guard layers.count == entries.count, layers.first?.position == 0,
              Set(layers.map(\.position)).count == layers.count,
              layers.allSatisfy({ (0..<32).contains($0.position) && $0.keys.count == keyboard.keyCount }) else {
            throw KeyfinderError.invalidLayout("expected distinct \(keyboard.displayName) layers with \(keyboard.keyCount) keys each, including layer 0.")
        }
        return self
    }
    public static func bundled() throws -> LayoutSnapshot {
        guard let url = CoreResources.bundle.url(forResource: "DemoLayout", withExtension: "json") else { throw KeyfinderError.invalidLayout("bundled layout is missing.") }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url)).validated()
    }
}

extension String {
    var nonEmpty: String? { let v = trimmingCharacters(in: .whitespacesAndNewlines); return v.isEmpty ? nil : v }
}
