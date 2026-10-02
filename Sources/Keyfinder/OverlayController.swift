import AppKit
import KeyfinderCore

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class OverlayController {
    let panel: OverlayPanel
    let keyboardView: KeyboardView
    var onPositionChange: ((Double, Double) -> Void)?
    private var pendingAppearance: DispatchWorkItem?
    private var generation = 0
    private var preferences = Preferences()
    private var observer: NSObjectProtocol?

    init(geometry: KeyboardGeometry) {
        keyboardView = KeyboardView(geometry: geometry)
        keyboardView.rendersContent = false
        panel = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Keyfinder overlay"
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.contentView = keyboardView
        keyboardView.onDragFinished = { [weak self] in self?.didDrag() }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.panel.isVisible == true { self?.position() } }
        }
    }

    func show(_ layer: PresentedLayer?, message: String? = nil, preferences: Preferences, preview: Bool = false, arranging: Bool = false, unverified: Bool = false, keyboard: KeyboardModel? = nil, immediate: Bool = false) {
        generation += 1
        pendingAppearance?.cancel(); pendingAppearance = nil
        self.preferences = preferences
        if let model = layer?.keyboard ?? keyboard, model != keyboardView.geometry.keyboard {
            guard let geometry = try? KeyboardGeometry.load(for: model) else { hide(); return }
            keyboardView.geometry = geometry
        }
        panel.appearance = preferences.appearance.appKit
        keyboardView.presentedLayer = layer
        keyboardView.message = message
        if keyboardView.preview != preview { keyboardView.preview = preview }
        if keyboardView.arranging != arranging { keyboardView.arranging = arranging }
        if keyboardView.unverified != unverified { keyboardView.unverified = unverified }
        if keyboardView.useKeyColors != preferences.useKeyColors { keyboardView.useKeyColors = preferences.useKeyColors }
        panel.ignoresMouseEvents = !arranging
        panel.alphaValue = preferences.opacity
        position()
        if panel.isVisible { return }
        if preferences.appearanceDelay == 0 || preview || arranging || immediate {
            present()
        } else {
            let expected = generation
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.generation == expected else { return }
                self.pendingAppearance = nil
                self.present()
            }
            pendingAppearance = work
            DispatchQueue.main.asyncAfter(deadline: .now() + preferences.appearanceDelay, execute: work)
        }
    }

    func hide() {
        generation += 1; pendingAppearance?.cancel(); pendingAppearance = nil
        keyboardView.rendersContent = false
        if panel.isVisible { panel.orderOut(nil) }
    }
    private func present() {
        keyboardView.rendersContent = true
        panel.orderFrontRegardless()
    }
    func close() {
        hide()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        panel.close()
    }
    private var selectedScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.displayID == preferences.screenID }) ?? NSScreen.main ?? NSScreen.screens.first
    }
    private func position() {
        guard let screen = selectedScreen else { return }
        let bounds = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        var width = min(preferences.width, bounds.width)
        var height = keyboardView.presentedLayer == nil ? 165 : KeyboardView.height(forWidth: width, geometry: keyboardView.geometry)
        if height > bounds.height {
            width = max(250, (bounds.height - KeyboardView.header - KeyboardView.padding) / keyboardView.geometry.height * keyboardView.geometry.width + KeyboardView.padding * 2)
            height = KeyboardView.height(forWidth: width, geometry: keyboardView.geometry)
        }
        let rect = NSRect(x: bounds.minX + (bounds.width - width) * preferences.horizontalPosition,
                          y: bounds.minY + (bounds.height - height) * preferences.verticalPosition, width: width, height: height)
        if panel.frame != rect { panel.setFrame(rect, display: true) }
    }
    private func didDrag() {
        guard let screen = panel.screen ?? selectedScreen else { return }
        let bounds = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        let x = max(0, min(1, (panel.frame.minX - bounds.minX) / max(1, bounds.width - panel.frame.width)))
        let y = max(0, min(1, (panel.frame.minY - bounds.minY) / max(1, bounds.height - panel.frame.height)))
        onPositionChange?(x, y)
    }
}

extension NSScreen {
    var displayID: UInt32 { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
}
