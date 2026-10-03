import AppKit
import Carbon
import SwiftUI
import KeyfinderCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, NSMenuItemValidation {
    private var model: AppModel?
    private(set) var statusItem: NSStatusItem?
    private(set) var settingsWindow: NSWindow?
    private let statusLine = NSMenuItem(title: "Waiting for your keyboard", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
    private let backgroundLaunch: Bool
    private let defaults: UserDefaults

    init(backgroundLaunch: Bool = false, defaults: UserDefaults = .standard, model: AppModel? = nil) {
        self.backgroundLaunch = backgroundLaunch; self.defaults = defaults; self.model = model
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            if model == nil {
                let geometry = try KeyboardGeometry.load()
                let overlay = OverlayController(geometry: geometry)
                let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("Keyfinder/Layouts", isDirectory: true)
                model = AppModel(geometry: geometry, monitor: HIDMonitor(), repository: LayoutRepository(directory: directory), defaults: defaults, overlay: overlay, hotKey: HoldHotKey())
            }
            guard let model else { return }
            configureApplicationMenu()
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            self.statusItem = statusItem
            statusItem.isVisible = model.preferences.showMenuBarIcon
            statusItem.button?.image = Logo.menuBarImage()
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
            model.onMenuBarVisibilityChange = { [weak self] visible in self?.statusItem?.isVisible = visible }
            model.onAppearanceChange = { [weak self] appearance in self?.settingsWindow?.appearance = appearance.appKit }
            model.start()
            updateMenu()
            let launchEvent = NSAppleEventManager.shared().currentAppleEvent
            let loginLaunch = launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
            if !backgroundLaunch && !loginLaunch && (!model.preferences.showMenuBarIcon || !defaults.bool(forKey: "hasLaunched")) {
                defaults.set(true, forKey: "hasLaunched")
                openSettings()
            }
        } catch {
            let alert = NSAlert(); alert.messageText = "Keyfinder could not start"; alert.informativeText = error.localizedDescription
            alert.runModal(); NSApp.terminate(nil)
        }
    }

    private func configureApplicationMenu() {
        // Status-item shortcuts only work while its dropdown is tracking. The
        // application menu handles standard commands whenever Settings is key.
        let menu = NSMenu()
        let application = NSMenu(title: "Keyfinder")
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        application.addItem(settings)
        application.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Keyfinder", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        application.addItem(quit)
        let applicationItem = NSMenuItem()
        applicationItem.submenu = application
        menu.addItem(applicationItem)

        let file = NSMenu(title: "File")
        // A nil target routes Close to the key window through the responder chain.
        file.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let fileItem = NSMenuItem()
        fileItem.submenu = file
        menu.addItem(fileItem)

        // Text fields find editing commands through the main menu's key equivalents.
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        edit.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editItem = NSMenuItem()
        editItem.submenu = edit
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    func menuWillOpen(_ menu: NSMenu) { updateMenu() }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(togglePause) || item.action == #selector(retryConnection) {
            return model?.isFlashingFirmware != true
        }
        return true
    }
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
            window.backgroundColor = Theme.background
            window.appearance = model.preferences.appearance.appKit
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.minSize = NSSize(width: 940, height: 810)
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindow?.isMiniaturized == true { settingsWindow?.deminiaturize(nil) }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { model?.endOverlayPreview() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.isFlashingFirmware == true else { return .terminateNow }
        openSettings()
        let alert = NSAlert()
        alert.messageText = "Firmware flashing is still running"
        alert.informativeText = "Wait for Zapp to finish before quitting Keyfinder. Interrupting it can leave your keyboard in bootloader mode."
        alert.addButton(withTitle: "Keep flashing")
        if let window = settingsWindow, window.attachedSheet == nil { alert.beginSheetModal(for: window) }
        return .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) {
        settingsWindow?.close()
        model?.onStatusChange = nil; model?.onMenuBarVisibilityChange = nil
        model?.onAppearanceChange = nil
        model?.stop()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }
}
