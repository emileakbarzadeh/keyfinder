import Foundation

public struct KeyGeometry: Codable, Equatable, Sendable {
    public let index: Int
    public let row: Int
    public let column: Int
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let rotation: Double
    public let pivotX: Double
    public let pivotY: Double

    public func transformed(x: Double, y: Double) -> (x: Double, y: Double) {
        let angle = rotation * .pi / 180
        let dx = x - pivotX, dy = y - pivotY
        return (pivotX + dx * cos(angle) - dy * sin(angle), pivotY + dx * sin(angle) + dy * cos(angle))
    }
}

public enum MoonlanderGeometry {
    public static let width = 17.0
    public static let height = 8.083
    public static func load() throws -> [KeyGeometry] {
        guard let url = CoreResources.bundle.url(forResource: "Moonlander", withExtension: "json") else { throw KeyfinderError.invalidLayout("keyboard geometry is missing.") }
        let keys = try JSONDecoder().decode([KeyGeometry].self, from: Data(contentsOf: url))
        guard keys.count == 72, keys.map(\.index) == Array(0..<72) else { throw KeyfinderError.invalidLayout("invalid keyboard geometry.") }
        return keys
    }
}
