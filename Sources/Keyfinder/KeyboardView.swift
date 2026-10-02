import AppKit
import KeyfinderCore

/// A static view: AppKit draws it only when content, size, or appearance changes.
class KeyboardView: NSView, NSViewToolTipOwner {
    static let padding: CGFloat = 22
    static let header: CGFloat = 68
    var geometry: KeyboardGeometry { didSet { if geometry != oldValue { rebuildTooltips(); needsDisplay = true } } }
    var presentedLayer: PresentedLayer? { didSet { if presentedLayer != oldValue { rebuildTooltips(); needsDisplay = true } } }
    var message: String? { didSet { if message != oldValue { needsDisplay = true } } }
    var preview = false { didSet { if preview != oldValue { rebuildTooltips() }; needsDisplay = true } }
    var useKeyColors = true { didSet { needsDisplay = true } }
    var arranging = false { didSet { needsDisplay = true } }
    var unverified = false { didSet { needsDisplay = true } }
    var selectedIndex: Int? { didSet { needsDisplay = true } }
    var onSelect: ((Int) -> Void)?
    var onDragFinished: (() -> Void)?
    var rendersContent = true {
        didSet { if rendersContent && !oldValue { needsDisplay = true } }
    }
    private(set) var drawCount = 0
    private var tooltipText: [NSView.ToolTipTag: String] = [:]
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // The overlay requests a fresh draw when shown again. A hidden panel
        // need not repaint its backing store for a system appearance change.
        needsDisplay = rendersContent
    }

    init(geometry: KeyboardGeometry) { self.geometry = geometry; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func height(forWidth width: CGFloat, geometry: KeyboardGeometry) -> CGFloat {
        header + padding + (width - padding * 2) / geometry.width * geometry.height
    }
    private var unit: CGFloat { max(1, (bounds.width - Self.padding * 2) / geometry.width) }
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
        // AppKit may invalidate even an ordered-out window on appearance changes.
        guard rendersContent else { return }
        drawCount += 1
        let colors = Theme.palette(for: effectiveAppearance)
        if presentedLayer != nil { drawKeyGlow(color: colors.background) }
        drawText(presentedLayer?.name ?? "Keyfinder", in: NSRect(x: 25, y: 18, width: bounds.width * 0.56, height: 25), size: 20, weight: .semibold, color: colors.text, align: .left, glow: colors.background)
        let subtitle = (presentedLayer.map { "\($0.layoutTitle)  /  \($0.keyboardName)" } ?? geometry.keyboard.displayName) + (unverified ? "  ·  Unverified revision" : "")
        drawText(subtitle, in: NSRect(x: 26, y: 43, width: bounds.width * 0.58, height: 15), size: 10, color: colors.mutedText, align: .left, glow: colors.background)
        if let layer = presentedLayer {
            for key in geometry.keys {
                guard layer.keys.indices.contains(key.index) else { continue }
                draw(key, presentation: layer.keys[key.index], colors: colors)
            }
        } else {
            drawText(message ?? "Waiting for the keyboard", in: NSRect(x: 35, y: 92, width: bounds.width - 70, height: max(60, bounds.height - 115)), size: 14, color: colors.text, glow: colors.background)
        }
    }

    private func drawKeyGlow(color: NSColor) {
        // Blur the whole silhouette once instead of creating a shadow per key.
        let silhouette = NSBezierPath()
        for key in geometry.keys { silhouette.append(path(for: key)) }
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color.withAlphaComponent(0.95)
        shadow.shadowBlurRadius = min(18, max(10, unit * 0.3))
        shadow.shadowOffset = .zero
        shadow.set()
        color.setFill(); silhouette.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func draw(_ key: KeyGeometry, presentation: PresentedKey, colors: Theme.Palette) {
        let path = path(for: key)
        let inherited = presentation.appearance == .inherited || presentation.appearance == .ambiguous
        let unknown = presentation.appearance == .unknown
        let accent = useKeyColors ? NSColor(hex: presentation.color) : nil
        let base = inherited ? colors.inheritedKey : colors.key
        let fill = unknown ? colors.background : accent.map { Theme.tinted(base, with: $0, amount: 0.12) } ?? base
        fill.setFill(); path.fill()
        (selectedIndex == key.index || unknown ? Theme.orange : (accent?.withAlphaComponent(0.70) ?? colors.border)).setStroke()
        path.lineWidth = selectedIndex == key.index ? 2 : 0.8; path.stroke()
        let point = center(for: key)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform(); transform.translateX(by: point.x, yBy: point.y); transform.rotate(byDegrees: key.rotation); transform.concat()
        let width = key.width * unit - 9
        let height = key.height * unit - 8
        let color = unknown ? colors.accentText : inherited ? colors.mutedText : colors.text
        let baseSize = min(19, max(10, unit * 0.30))
        let y: CGFloat = presentation.secondary.isEmpty ? -baseSize * 0.68 : -height * 0.30
        drawText(presentation.label, in: NSRect(x: -width / 2, y: y, width: width, height: baseSize * 1.45), size: baseSize, weight: .medium, color: color, shrink: true)
        if !presentation.secondary.isEmpty {
            drawText(presentation.secondary, in: NSRect(x: -width / 2 + 1, y: height * 0.13, width: width - 2, height: min(15, unit * 0.25)), size: min(10, unit * 0.185), color: colors.mutedText, shrink: true)
        }
        if inherited {
            drawText("↳", in: NSRect(x: width / 2 - 11, y: -height / 2 + 1, width: 10, height: 10), size: 8, color: colors.mutedText)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawText(_ text: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, align: NSTextAlignment = .center, shrink: Bool = false, glow: NSColor? = nil) {
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
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph]
        if let glow {
            let shadow = NSShadow()
            shadow.shadowColor = glow.withAlphaComponent(0.95)
            shadow.shadowBlurRadius = 7
            shadow.shadowOffset = .zero
            var backdrop = attributes
            backdrop[.foregroundColor] = glow
            backdrop[.shadow] = shadow
            backdrop[.strokeColor] = glow
            backdrop[.strokeWidth] = -24
            (text as NSString).draw(in: rect, withAttributes: backdrop)
        }
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        if arranging {
            window?.performDrag(with: event)
            onDragFinished?()
        } else if let onSelect {
            let point = convert(event.locationInWindow, from: nil)
            if let key = geometry.keys.first(where: { path(for: $0).contains(point) }) { selectedIndex = key.index; onSelect(key.index) }
        }
    }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); rebuildTooltips() }
    private func rebuildTooltips() {
        removeAllToolTips()
        tooltipText.removeAll(keepingCapacity: true)
        guard preview, let layer = presentedLayer else { return }
        for key in geometry.keys where layer.keys.indices.contains(key.index) {
            // AppKit does not retain the owner. A temporary NSString bridge can
            // be freed before the hover timer fires; the view owns this data.
            let tag = addToolTip(path(for: key).bounds, owner: self, userData: nil)
            tooltipText[tag] = layer.keys[key.index].detail
        }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard view === self, preview else { return "" }
        return tooltipText[tag] ?? ""
    }
}

extension NSColor {
    convenience init?(hex: String?) {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
