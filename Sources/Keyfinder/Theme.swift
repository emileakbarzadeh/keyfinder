import AppKit

enum Theme {
    static let blue = NSColor(srgbRed: 0, green: 48.0 / 255, blue: 73.0 / 255, alpha: 1)
    static let red = NSColor(srgbRed: 214.0 / 255, green: 40.0 / 255, blue: 40.0 / 255, alpha: 1)
    static let orange = NSColor(srgbRed: 247.0 / 255, green: 127.0 / 255, blue: 0, alpha: 1)
    static let parchment = NSColor(srgbRed: 244.0 / 255, green: 243.0 / 255, blue: 238.0 / 255, alpha: 1)

    static let surface = blue.blended(withFraction: 0.06, of: parchment)!
    static let key = blue.blended(withFraction: 0.10, of: parchment)!
    static let mutedText = blue.blended(withFraction: 0.74, of: parchment)!
    static let border = parchment.withAlphaComponent(0.24)
}
