import AppKit
import SwiftUI

enum AppAppearance: String, Codable, CaseIterable {
    case system, light, dark

    var title: String { rawValue.capitalized }
    var appKit: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum Theme {
    // Bright accents sit on neutral surfaces in both appearances.
    static let orange = NSColor(hex: "#F77F00")!
    static let red = NSColor(hex: "#D62828")!
    static let parchment = NSColor(hex: "#F4F3EE")!
    static let ink = NSColor(hex: "#111315")!

    struct Palette {
        let background, surface, key, inheritedKey, text, mutedText, border, accentText: NSColor
    }

    static let dark = Palette(
        background: ink, surface: NSColor(hex: "#1C1F22")!, key: NSColor(hex: "#292D31")!,
        inheritedKey: NSColor(hex: "#1C1F22")!, text: parchment, mutedText: NSColor(hex: "#B3B8BE")!,
        border: NSColor(hex: "#454A50")!, accentText: orange
    )
    static let light = Palette(
        background: parchment, surface: .white, key: .white,
        inheritedKey: NSColor(hex: "#E9E7E1")!, text: NSColor(hex: "#202326")!, mutedText: NSColor(hex: "#50565B")!,
        border: NSColor(hex: "#CECFCA")!, accentText: NSColor(hex: "#A64B00")!
    )

    static func palette(for appearance: NSAppearance) -> Palette {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    }

    // Native dynamic colors let SwiftUI and window chrome follow macOS changes.
    private static func adaptive(_ keyPath: KeyPath<Palette, NSColor>) -> NSColor {
        NSColor(name: nil) { palette(for: $0)[keyPath: keyPath] }
    }
    static let background = adaptive(\.background)
    static let surface = adaptive(\.surface)
    static let key = adaptive(\.key)
    static let text = adaptive(\.text)
    static let mutedText = adaptive(\.mutedText)
    static let border = adaptive(\.border)

    static func tinted(_ base: NSColor, with accent: NSColor, amount: CGFloat) -> NSColor {
        guard let base = base.usingColorSpace(.sRGB), let accent = accent.usingColorSpace(.sRGB) else { return base }
        return NSColor(srgbRed: base.redComponent + (accent.redComponent - base.redComponent) * amount,
                       green: base.greenComponent + (accent.greenComponent - base.greenComponent) * amount,
                       blue: base.blueComponent + (accent.blueComponent - base.blueComponent) * amount, alpha: 1)
    }
}
