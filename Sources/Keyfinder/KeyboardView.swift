import AppKit
import KeyfinderCore

/// A static view: AppKit draws it only when content, size, or appearance changes.
final class KeyboardView: NSView {
    static let padding: CGFloat = 22
    static let header: CGFloat = 68
    static let footer: CGFloat = 26
    let geometry: [KeyGeometry]
    var presentedLayer: PresentedLayer? { didSet { if presentedLayer != oldValue { rebuildTooltips(); needsDisplay = true } } }
    var message: String? { didSet { if message != oldValue { needsDisplay = true } } }
    var preview = false { didSet { needsDisplay = true } }
    var useKeyColors = true { didSet { needsDisplay = true } }
    var arranging = false { didSet { needsDisplay = true } }
    var unverified = false { didSet { needsDisplay = true } }
    var selectedIndex: Int? { didSet { needsDisplay = true } }
    var onSelect: ((Int) -> Void)?
    var onDragFinished: (() -> Void)?
    private(set) var drawCount = 0
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    init(geometry: [KeyGeometry]) { self.geometry = geometry; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func height(forWidth width: CGFloat) -> CGFloat {
        header + footer + (width - padding * 2) / MoonlanderGeometry.width * MoonlanderGeometry.height
    }
    private var unit: CGFloat { max(1, (bounds.width - Self.padding * 2) / MoonlanderGeometry.width) }
    private func center(for key: KeyGeometry) -> NSPoint {
        let point = key.transformed(x: key.x + key.width / 2, y: key.y + key.height / 2)
        return NSPoint(x: Self.padding + point.x * unit, y: Self.header + point.y * unit)
    }
    private func path(for key: KeyGeometry) -> NSBezierPath {
        let inset = unit * 0.045
        let rect = NSRect(x: -key.width * unit / 2 + inset, y: -key.height * unit / 2 + inset,
                          width: key.width * unit - inset * 2, height: key.height * unit - inset * 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: unit * 0.115, yRadius: unit * 0.115)
        var transform = AffineTransform()
        let center = center(for: key)
        transform.translate(x: center.x, y: center.y); transform.rotate(byDegrees: key.rotation)
        path.transform(using: transform)
        return path
    }

    override func draw(_ dirtyRect: NSRect) {
        drawCount += 1
        NSColor(calibratedRed: 0.065, green: 0.075, blue: 0.095, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 19, yRadius: 19).fill()
        NSColor.white.withAlphaComponent(0.13).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 19, yRadius: 19)
        border.lineWidth = 1; border.stroke()

        drawText(presentedLayer?.name ?? "Keyfinder", in: NSRect(x: 25, y: 18, width: bounds.width * 0.56, height: 25), size: 20, weight: .semibold, color: .white, align: .left)
        let subtitle = (presentedLayer.map { "\($0.layoutTitle)  /  Moonlander" } ?? "Moonlander") + (unverified ? "  ·  Unverified revision" : "")
        drawText(subtitle, in: NSRect(x: 26, y: 43, width: bounds.width * 0.58, height: 15), size: 10, color: .white.withAlphaComponent(0.48), align: .left)
        let badge = arranging ? "DRAG TO POSITION" : preview ? "PREVIEW" : "LIVE"
        let badgeWidth: CGFloat = arranging ? 126 : 69
        let badgeRect = NSRect(x: bounds.width - badgeWidth - 25, y: 22, width: badgeWidth, height: 24)
        NSColor.systemTeal.withAlphaComponent(0.13).setFill(); NSBezierPath(roundedRect: badgeRect, xRadius: 7, yRadius: 7).fill()
        drawText(badge, in: badgeRect.insetBy(dx: 3, dy: 6), size: 9, weight: .semibold, color: .systemTeal)

        if let layer = presentedLayer {
            for key in geometry {
                guard layer.keys.indices.contains(key.index) else { continue }
                draw(key, presentation: layer.keys[key.index])
            }
            let legend = arranging ? "Drag the keyboard, then choose Done arranging in Settings." :
                layer.ambiguousCount > 0 ? "↳  Inherited keys show alternatives when lower layers may differ." :
                layer.inheritedCount > 0 ? "↳  Dimmed keys inherit their action from a lower layer." : "Tap actions are primary. Hold actions appear below."
            drawText(legend, in: NSRect(x: 25, y: bounds.height - 23, width: bounds.width - 50, height: 13), size: 10, color: .white.withAlphaComponent(0.42), align: .left)
        } else {
            drawText(message ?? "Waiting for the keyboard", in: NSRect(x: 35, y: 92, width: bounds.width - 70, height: max(60, bounds.height - 115)), size: 14, color: .white.withAlphaComponent(0.8))
        }
    }

    private func draw(_ key: KeyGeometry, presentation: PresentedKey) {
        let path = path(for: key)
        let inherited = presentation.appearance == .inherited || presentation.appearance == .ambiguous
        let accent = useKeyColors ? NSColor(hex: presentation.color) : nil
        let fill = accent?.blended(withFraction: 0.88, of: NSColor(calibratedWhite: 0.12, alpha: 1)) ??
            NSColor(calibratedWhite: inherited ? 0.105 : 0.155, alpha: 1)
        fill.setFill(); path.fill()
        (selectedIndex == key.index ? NSColor.systemTeal : (accent?.withAlphaComponent(0.45) ?? NSColor.white.withAlphaComponent(inherited ? 0.09 : 0.16))).setStroke()
        path.lineWidth = selectedIndex == key.index ? 2 : 0.8; path.stroke()
        let point = center(for: key)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform(); transform.translateX(by: point.x, yBy: point.y); transform.rotate(byDegrees: key.rotation); transform.concat()
        let width = key.width * unit - 9
        let height = key.height * unit - 8
        let color: NSColor = presentation.appearance == .unknown ? .systemOrange : .white.withAlphaComponent(inherited ? 0.53 : 0.96)
        let baseSize = min(19, max(10, unit * 0.30))
        let y: CGFloat = presentation.secondary.isEmpty ? -baseSize * 0.68 : -height * 0.30
        drawText(presentation.label, in: NSRect(x: -width / 2, y: y, width: width, height: baseSize * 1.45), size: baseSize, weight: .medium, color: color, shrink: true)
        if !presentation.secondary.isEmpty {
            drawText(presentation.secondary, in: NSRect(x: -width / 2 + 1, y: height * 0.13, width: width - 2, height: min(15, unit * 0.25)), size: min(10, unit * 0.185), color: .white.withAlphaComponent(0.46), shrink: true)
        }
        if inherited {
            drawText("↳", in: NSRect(x: width / 2 - 11, y: -height / 2 + 1, width: 10, height: 10), size: 8, color: .systemTeal.withAlphaComponent(0.6))
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawText(_ text: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, align: NSTextAlignment = .center, shrink: Bool = false) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = align; paragraph.lineBreakMode = .byTruncatingTail
        var fontSize = size
        if shrink {
            let measured = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width
            if measured > rect.width - 4 { fontSize = max(5.5, size * (rect.width - 4) / measured) }
            // NSString's paragraph drawing reserves a line-fragment margin and
            // can ellipsize even a measured-to-fit label. Draw fitted key legends
            // at a point instead, so the target layer number is never truncated.
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: weight), .foregroundColor: color]
            let actual = (text as NSString).size(withAttributes: attributes)
            let x = align == .left ? rect.minX : rect.midX - actual.width / 2
            (text as NSString).draw(at: NSPoint(x: x, y: rect.midY - actual.height / 2), withAttributes: attributes)
            return
        }
        (text as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph])
    }

    override func mouseDown(with event: NSEvent) {
        if arranging {
            window?.performDrag(with: event)
            onDragFinished?()
        } else if let onSelect {
            let point = convert(event.locationInWindow, from: nil)
            if let key = geometry.first(where: { path(for: $0).contains(point) }) { selectedIndex = key.index; onSelect(key.index) }
        }
    }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); rebuildTooltips() }
    private func rebuildTooltips() {
        removeAllToolTips()
        guard preview, let layer = presentedLayer else { return }
        for key in geometry where layer.keys.indices.contains(key.index) {
            addToolTip(path(for: key).bounds, owner: layer.keys[key.index].detail as NSString, userData: nil)
        }
    }
}

extension NSColor {
    convenience init?(hex: String?) {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(calibratedRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
