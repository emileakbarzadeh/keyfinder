import AppKit
import SwiftUI
import KeyfinderCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var model: AppModel?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private let statusLine = NSMenuItem(title: "Waiting for Moonlander", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
    private let backgroundLaunch: Bool

    init(backgroundLaunch: Bool = false) { self.backgroundLaunch = backgroundLaunch; super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let geometry = try MoonlanderGeometry.load()
            let overlay = OverlayController(geometry: geometry)
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Keyfinder/Layouts", isDirectory: true)
            let model = AppModel(geometry: geometry, monitor: HIDMonitor(), repository: LayoutRepository(directory: directory), overlay: overlay)
            self.model = model
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            self.statusItem = statusItem
            statusItem.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keyfinder")
            statusItem.button?.image?.isTemplate = true
            let menu = NSMenu(); menu.delegate = self
            statusLine.isEnabled = false; menu.addItem(statusLine); menu.addItem(.separator())
            let preview = NSMenuItem(title: "Preview keyboard…", action: #selector(openSettings), keyEquivalent: "")
            preview.target = self; menu.addItem(preview)
            pauseItem.target = self; menu.addItem(pauseItem)
            let refresh = NSMenuItem(title: "Refresh Oryx preview", action: #selector(refreshLayout), keyEquivalent: "")
            refresh.target = self; menu.addItem(refresh)
            let retry = NSMenuItem(title: "Retry keyboard connection", action: #selector(retryConnection), keyEquivalent: "")
            retry.target = self; menu.addItem(retry)
            menu.addItem(.separator())
            let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            settings.target = self; menu.addItem(settings)
            let quit = NSMenuItem(title: "Quit Keyfinder", action: #selector(quitApp), keyEquivalent: "q")
            quit.target = self; menu.addItem(quit)
            statusItem.menu = menu
            model.onStatusChange = { [weak self] in self?.updateMenu() }
            model.start()
            updateMenu()
            if !backgroundLaunch && !UserDefaults.standard.bool(forKey: "hasLaunched") {
                UserDefaults.standard.set(true, forKey: "hasLaunched")
                openSettings()
            }
        } catch {
            let alert = NSAlert(); alert.messageText = "Keyfinder could not start"; alert.informativeText = error.localizedDescription
            alert.runModal(); NSApp.terminate(nil)
        }
    }

    func menuWillOpen(_ menu: NSMenu) { updateMenu() }
    private func updateMenu() {
        guard let model else { return }
        statusLine.title = model.status
        pauseItem.title = model.isPaused ? "Resume" : "Pause"
        statusItem?.button?.toolTip = "Keyfinder — \(model.status)"
    }
    @objc private func togglePause() { model?.togglePause() }
    @objc private func refreshLayout() { model?.refreshLayout() }
    @objc private func retryConnection() { model?.retryConnection() }
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc func openSettings() {
        guard let model else { return }
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Keyfinder"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.minSize = NSSize(width: 940, height: 810)
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { model?.endOverlayPreview() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }
    func applicationWillTerminate(_ notification: Notification) { model?.stop() }
}
