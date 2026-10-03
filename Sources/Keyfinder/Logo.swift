import AppKit

/// Keyfinder's logo: stacked layer plates with keys on the orange top layer.
/// Drawn in code so the app icon, menu bar icon, and Settings header stay sharp at every size.
enum Logo {
    private static let orangeSide = NSColor(hex: "#B85A00")!
    private static let plates: [(top: NSColor, side: NSColor)] = [
        (NSColor(hex: "#4A5058")!, NSColor(hex: "#33383E")!),
        (NSColor(hex: "#8A8F95")!, NSColor(hex: "#62676D")!),
        (Theme.orange, orangeSide),
    ]

    /// Draws the icon on Apple's 1024-point macOS grid, scaled into `rect`. Tiny
    /// renderings omit the keys, which would only blur at that size.
    static func drawIcon(in rect: NSRect, showsKeys: Bool = true) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scaleX(by: rect.width / 1024, yBy: rect.height / 1024)
        transform.concat()

        // An 824-point rounded square centered on the canvas, as macOS expects.
        let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
        NSGradient(starting: NSColor(hex: "#2B3036")!, ending: NSColor(hex: "#0E1012")!)?.draw(in: tile, angle: -90)

        // Plates span y 208 to 816, leaving equal 108-point margins inside the tile.
        let center: CGFloat = 512, halfWidth: CGFloat = 280, halfHeight: CGFloat = 158, depth: CGFloat = 32, spacing: CGFloat = 130
        for (index, colors) in plates.enumerated() {
            let y = 398 + CGFloat(index) * spacing
            let edge = NSBezierPath()
            edge.move(to: NSPoint(x: center - halfWidth, y: y))
            edge.line(to: NSPoint(x: center, y: y - halfHeight))
            edge.line(to: NSPoint(x: center + halfWidth, y: y))
            edge.line(to: NSPoint(x: center + halfWidth, y: y - depth))
            edge.line(to: NSPoint(x: center, y: y - halfHeight - depth))
            edge.line(to: NSPoint(x: center - halfWidth, y: y - depth))
            edge.close()
            colors.side.setFill(); edge.fill()
            colors.top.setFill(); diamond(NSPoint(x: center, y: y), halfWidth, halfHeight).fill()
            guard showsKeys, index == plates.count - 1 else { continue }
            // A 3x3 block of keys laid along the plate's isometric axes.
            Theme.parchment.setFill()
            for row in -1...1 {
                for column in -1...1 {
                    let u = CGFloat(column) * 0.3, v = CGFloat(row) * 0.3
                    let key = NSPoint(x: center + (u - v) * halfWidth, y: y + (u + v) * halfHeight)
                    diamond(key, halfWidth * 0.24, halfHeight * 0.24).fill()
                }
            }
        }
    }

    /// The full icon canvas, including Apple's transparent margin.
    static func iconImage(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            drawIcon(in: rect, showsKeys: size >= 64); return true
        }
    }

    /// The rounded square alone, filling the image, for use inside the app's own UI.
    static func tileImage(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let canvas = rect.width * 1024 / 824
            drawIcon(in: rect.insetBy(dx: (rect.width - canvas) / 2, dy: (rect.height - canvas) / 2), showsKeys: size >= 32)
            return true
        }
    }

    /// A monochrome template for the menu bar: the top layer filled, with the
    /// front edges of the two layers beneath it.
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let size = rect.width, center = size / 2, halfWidth = size * 0.42, halfHeight = size * 0.22
            NSColor.black.set()
            for (index, y) in [size * 0.30, size * 0.50, size * 0.70].enumerated() {
                let plate = diamond(NSPoint(x: center, y: y), halfWidth, halfHeight)
                if index == 2 { plate.fill(); continue }
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: y)).addClip()
                plate.lineWidth = size * 0.075; plate.lineJoinStyle = .round; plate.stroke()
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Keyfinder"
        return image
    }

    private static func diamond(_ center: NSPoint, _ halfWidth: CGFloat, _ halfHeight: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x, y: center.y + halfHeight))
        path.line(to: NSPoint(x: center.x + halfWidth, y: center.y))
        path.line(to: NSPoint(x: center.x, y: center.y - halfHeight))
        path.line(to: NSPoint(x: center.x - halfWidth, y: center.y))
        path.close()
        return path
    }
}
