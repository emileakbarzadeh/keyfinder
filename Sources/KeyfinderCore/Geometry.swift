import Foundation

public struct KeyGeometry: Codable, Equatable, Sendable {
    public let index: Int
    // Matrix metadata is optional; the overlay uses Oryx key indices only.
    public let row: Int?
    public let column: Int?
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

public struct KeyboardGeometry: Equatable, Sendable {
    public let keyboard: KeyboardModel
    public let width: Double
    public let height: Double
    public let keys: [KeyGeometry]

    private static let definitions: [KeyboardModel: Result<KeyboardGeometry, Error>] = Dictionary(
        uniqueKeysWithValues: KeyboardModel.allCases.map { keyboard in
            (keyboard, Result { try read(keyboard) })
        }
    )
    public static func load(for keyboard: KeyboardModel = .moonlander) throws -> KeyboardGeometry {
        try definitions[keyboard]!.get()
    }
    private static func read(_ keyboard: KeyboardModel) throws -> KeyboardGeometry {
        guard let url = CoreResources.bundle.url(forResource: keyboard.resourceName, withExtension: "json") else {
            throw KeyfinderError.invalidLayout("\(keyboard.displayName) geometry is missing.")
        }
        let keys = try JSONDecoder().decode([KeyGeometry].self, from: Data(contentsOf: url))
        let size: (Double, Double)
        switch keyboard {
        case .moonlander: size = (17, 8.083)
        case .voyager: size = (14, 5.6)
        case .ergodoxEZ: size = (20, 8)
        }
        guard keys.count == keyboard.keyCount, keys.map(\.index) == Array(0..<keyboard.keyCount),
              keys.allSatisfy({ key in
                  key.width > 0 && key.height > 0 && [key.x, key.y, key.width, key.height, key.rotation, key.pivotX, key.pivotY].allSatisfy(\.isFinite)
              }) else { throw KeyfinderError.invalidLayout("invalid \(keyboard.displayName) geometry.") }
        return KeyboardGeometry(keyboard: keyboard, width: size.0, height: size.1, keys: keys)
    }
}
