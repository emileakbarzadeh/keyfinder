import Foundation

struct Preferences: Codable, Equatable {
    var layoutURL = "https://configure.zsa.io/moonlander/layouts/exampleLayout/latest/0"
    var width: Double = 920
    var opacity: Double = 0.94
    var appearanceDelay: Double = 0
    var screenID: UInt32 = 0
    var horizontalPosition: Double = 0.5
    var verticalPosition: Double = 0.035
    var useKeyColors = true

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
