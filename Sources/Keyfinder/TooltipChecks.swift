import AppKit
import KeyfinderCore

extension Diagnostics {
    static func checkKeyboardTooltips() throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        let geometry = try KeyboardGeometry.load()
        let layers = LabelResolver.prepare(try LayoutSnapshot.bundled())
        let view = TooltipProbeView(geometry: geometry)
        view.preview = true
        // AppKit does not retain addToolTip's owner. Observe the actual owners
        // passed to it, without keeping temporary NSString bridges alive here.
        autoreleasepool {
            view.presentedLayer = layers[1]
            view.setFrameSize(NSSize(width: 920, height: 450))
        }
        checks["tooltip_owners_survive_autorelease_pool"] = !view.registrations.isEmpty
            && view.registrations.allSatisfy { $0.owner != nil }
        func detailsMatch() -> Bool {
            guard let layer = view.presentedLayer else { return false }
            let keys = view.geometry.keys.filter { layer.keys.indices.contains($0.index) }
            return view.registrations.count == keys.count && zip(view.registrations, keys).allSatisfy { registration, key in
                registration.text(in: view) == layer.keys[key.index].detail
            }
        }
        checks["tooltip_callbacks_return_full_key_details"] = detailsMatch()

        autoreleasepool { view.presentedLayer = layers[0] }
        checks["tooltip_layer_change_updates_details"] = detailsMatch()
        let oldRects = view.registrations.map(\.rect)
        autoreleasepool { view.setFrameSize(NSSize(width: 700, height: 360)) }
        checks["tooltip_resize_updates_regions_and_preserves_details"] = oldRects != view.registrations.map(\.rect) && detailsMatch()

        let pending = view.registrations
        view.preview = false
        checks["disabling_preview_clears_tooltips_and_stale_callbacks"] = view.registrations.isEmpty
            && pending.allSatisfy { $0.text(in: view) == "" }
        view.preview = true
        checks["enabling_preview_restores_tooltips"] = detailsMatch()
        view.presentedLayer = nil
        checks["clearing_layer_removes_tooltips"] = view.registrations.isEmpty

        view.geometry = try KeyboardGeometry.load(for: .voyager)
        try autoreleasepool { view.presentedLayer = LabelResolver.prepare(try keyboardFixture(.voyager))[1] }
        checks["tooltip_model_change_uses_current_keys"] = view.registrations.count == KeyboardModel.voyager.keyCount && detailsMatch()

        weak var releasedView: TooltipProbeView?
        autoreleasepool {
            let temporary = TooltipProbeView(geometry: geometry)
            temporary.preview = true; temporary.presentedLayer = layers[1]
            temporary.setFrameSize(NSSize(width: 920, height: 450))
            releasedView = temporary
        }
        checks["tooltips_do_not_retain_their_view"] = releasedView == nil
        return checks
    }
}

@MainActor private final class TooltipProbeView: KeyboardView {
    struct Registration {
        let tag: NSView.ToolTipTag
        let rect: NSRect
        weak var owner: AnyObject?
        let userData: UnsafeMutableRawPointer?

        @MainActor func text(in view: NSView) -> String? {
            (owner as? NSViewToolTipOwner)?.view(view, stringForToolTip: tag,
                                               point: NSPoint(x: rect.midX, y: rect.midY), userData: userData) ?? (owner as? String)
        }
    }
    private(set) var registrations: [Registration] = []

    override func addToolTip(_ rect: NSRect, owner: Any, userData data: UnsafeMutableRawPointer?) -> NSView.ToolTipTag {
        let tag = super.addToolTip(rect, owner: owner, userData: data)
        registrations.append(Registration(tag: tag, rect: rect, owner: owner as AnyObject, userData: data))
        return tag
    }

    override func removeAllToolTips() {
        super.removeAllToolTips()
        registrations.removeAll()
    }
}
