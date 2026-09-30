import Foundation

struct Preferences: Codable, Equatable {
    var layoutURL = ""
    var width: Double = 920
    var opacity: Double = 0.94
    var appearanceDelay: Double = 0
    var screenID: UInt32 = 0
    var horizontalPosition: Double = 0.5
    var verticalPosition: Double = 0.035
    var useKeyColors = true
    var showMenuBarIcon = true

    init() {}

    private enum CodingKeys: String, CodingKey {
        case layoutURL, width, opacity, appearanceDelay, screenID, horizontalPosition, verticalPosition, useKeyColors, showMenuBarIcon
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        layoutURL = try values.decodeIfPresent(String.self, forKey: .layoutURL) ?? layoutURL
        width = try values.decodeIfPresent(Double.self, forKey: .width) ?? width
        opacity = try values.decodeIfPresent(Double.self, forKey: .opacity) ?? opacity
        appearanceDelay = try values.decodeIfPresent(Double.self, forKey: .appearanceDelay) ?? appearanceDelay
        screenID = try values.decodeIfPresent(UInt32.self, forKey: .screenID) ?? screenID
        horizontalPosition = try values.decodeIfPresent(Double.self, forKey: .horizontalPosition) ?? horizontalPosition
        verticalPosition = try values.decodeIfPresent(Double.self, forKey: .verticalPosition) ?? verticalPosition
        useKeyColors = try values.decodeIfPresent(Bool.self, forKey: .useKeyColors) ?? useKeyColors
        showMenuBarIcon = try values.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? showMenuBarIcon
    }

    func clamped() -> Preferences {
        var copy = self
        copy.width = width.isFinite ? min(1500, max(620, width)) : 920
        copy.opacity = opacity.isFinite ? min(1, max(0.4, opacity)) : 0.94
        copy.appearanceDelay = appearanceDelay.isFinite ? min(0.5, max(0, appearanceDelay)) : 0
        copy.horizontalPosition = horizontalPosition.isFinite ? min(1, max(0, horizontalPosition)) : 0.5
        copy.verticalPosition = verticalPosition.isFinite ? min(1, max(0, verticalPosition)) : 0.035
        return copy
    }
    static func load(from defaults: UserDefaults) -> Preferences {
        guard let data = defaults.data(forKey: "preferences"), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Preferences() }
        return value.clamped()
    }
    func save(to defaults: UserDefaults) { if let data = try? JSONEncoder().encode(clamped()) { defaults.set(data, forKey: "preferences") } }
}
