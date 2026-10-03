import AppKit
import Combine
import KeyfinderCore
import ServiceManagement

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var preferences: Preferences
    @Published private(set) var previewSnapshot: LayoutSnapshot?
    @Published private(set) var previewLayers: [Int: PresentedLayer] = [:]
    @Published var previewLayerIndex = 1
    @Published var selectedKeyIndex: Int?
    @Published private(set) var status = "Waiting for your keyboard"
    @Published private(set) var connectedKeyboardName: String?
    @Published private(set) var connectedKeyboardModel: KeyboardModel?
    @Published private(set) var connectionDetail = ""
    @Published private(set) var notice: String?
    @Published private(set) var isPaused = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isPreviewingOverlay = false
    @Published private(set) var isArranging = false
    @Published private(set) var isHoldingTypingLayer = false
    @Published private(set) var isRecordingHotKey = false
    @Published private(set) var isFlashingFirmware = false
    @Published private(set) var hotKeyError: String?
    @Published private(set) var connected = false
    @Published private(set) var installedRevision: String?
    @Published private(set) var currentLayer: Int?
    @Published private(set) var identityVerified = false
    @Published private(set) var protocolVersion: Int?
    @Published private(set) var launchAtLogin = false
    @Published private(set) var geometry: KeyboardGeometry
    let overlay: OverlayController
    let firmware: FirmwareFlasher
    private let monitor: any KeyboardMonitoring
    private let repository: LayoutRepository
    private let defaults: UserDefaults
    private let hotKey: (any HoldHotKeyMonitoring)?
    private var running = false
    private var sleeping = false
    private var sessionActive = true
    private var suspended: Bool { sleeping || !sessionActive }
    private var session = LiveSession()
    private var liveLayers: [Int: PresentedLayer] = [:]
    private var installedTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var previewGeneration = UUID()
    private var observers: [NSObjectProtocol] = []
    private var blockingProblem: String?
    private var layoutFailure: String?
    // Set by a successful flash; the next installed layout replaces the preview.
    private var previewFollowsNextInstall = false
    var onStatusChange: (() -> Void)?
    var onMenuBarVisibilityChange: ((Bool) -> Void)?
    var onAppearanceChange: ((AppAppearance) -> Void)?

    init(geometry: KeyboardGeometry, monitor: any KeyboardMonitoring, repository: LayoutRepository,
         defaults: UserDefaults = .standard, overlay: OverlayController, hotKey: (any HoldHotKeyMonitoring)? = nil,
         firmware: FirmwareFlasher? = nil) {
        self.geometry = geometry; self.monitor = monitor; self.repository = repository; self.defaults = defaults; self.overlay = overlay
        preferences = Preferences.load(from: defaults)
        self.hotKey = hotKey
        self.firmware = firmware ?? FirmwareFlasher(runner: ZappRunner())
        self.firmware.onFlashingChange = { [weak self] active in self?.setFlashingFirmware(active) }
        hotKey?.onChange = { [weak self] held in self?.receiveHotKey(held) }
        if let bundled = try? LayoutSnapshot.bundled() {
            previewSnapshot = bundled; previewLayers = LabelResolver.prepare(bundled)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        monitor.onEvent = { [weak self] event in self?.receive(event) }
        overlay.onPositionChange = { [weak self] x, y in
            guard let self else { return }
            var updated = self.preferences
            updated.horizontalPosition = x; updated.verticalPosition = y
            if let screen = self.overlay.panel.screen { updated.screenID = screen.displayID }
            self.setPreferences(updated)
        }
    }

    func start(observeSleep: Bool = true) {
        guard !running else { return }
        running = true
        if !isPaused && !suspended && !isFlashingFirmware { monitor.start() }
        updateHotKeyRegistration()
        let previewKeyboard = defaults.string(forKey: "previewKeyboard").flatMap(KeyboardModel.init(rawValue:)) ?? .moonlander
        if let serial = defaults.string(forKey: "previewIdentity"), let identity = try? LayoutIdentity(serial: serial, keyboard: previewKeyboard) {
            let generation = previewGeneration
            previewTask = Task { [weak self, repository] in
                guard let snapshot = await repository.cached(identity), !Task.isCancelled,
                      let self, self.previewGeneration == generation else { return }
                self.setPreview(snapshot)
            }
        }
        guard observeSleep else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setSystemState(sleeping: true) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setSystemState(sleeping: false) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setSystemState(sessionActive: false) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setSystemState(sessionActive: true) }
        })
    }

    func stop() {
        running = false; isHoldingTypingLayer = false; isRecordingHotKey = false
        if !isFlashingFirmware { firmware.clear() }
        hotKey?.stop()
        installedTask?.cancel(); installedTask = nil
        previewTask?.cancel(); previewTask = nil
        monitor.stop(); overlay.close()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }
    private func suspend() {
        installedTask?.cancel(); previewTask?.cancel()
        isRefreshing = false
        isPreviewingOverlay = false; isArranging = false
        isHoldingTypingLayer = false
        hotKey?.stop()
        monitor.stop(); overlay.hide()
    }

    func setSystemState(sleeping: Bool? = nil, sessionActive: Bool? = nil) {
        let wasSuspended = suspended
        if let sleeping { self.sleeping = sleeping }
        if let sessionActive { self.sessionActive = sessionActive }
        guard running, suspended != wasSuspended else { return }
        if suspended { suspend() }
        else {
            if !isPaused && !isFlashingFirmware { monitor.start() }
            updateHotKeyRegistration()
        }
    }

    private func receiveHotKey(_ held: Bool) {
        let held = held && running && !isPaused && !suspended && !isFlashingFirmware && !isRecordingHotKey && !isArranging && preferences.typingLayerHotKeyEnabled
        guard isHoldingTypingLayer != held else { return }
        isHoldingTypingLayer = held; synchronizeOverlay()
    }
    private func resetTypingLayerHold() {
        isHoldingTypingLayer = false
        hotKey?.resetHeldState()
    }
    func setHotKeyRecording(_ recording: Bool) {
        guard isRecordingHotKey != recording else { return }
        isRecordingHotKey = recording
        resetTypingLayerHold(); updateHotKeyRegistration(); synchronizeOverlay()
    }
    func updateHotKeyRegistration() {
        guard running, !isPaused, !suspended, !isFlashingFirmware, !isRecordingHotKey, preferences.typingLayerHotKeyEnabled else {
            hotKey?.stop(); hotKeyError = nil; return
        }
        do { try hotKey?.register(preferences.typingLayerHotKey); hotKeyError = nil }
        catch { hotKeyError = error.localizedDescription }
    }

    func receive(_ event: KeyboardEvent) {
        // Closing HID can leave callbacks queued. Zapp owns the connection
        // until its process has exited, including bootloader re-enumeration.
        if isFlashingFirmware { return }
        switch event {
        case .connected(let device):
            resetTypingLayerHold()
            installedTask?.cancel()
            guard let keyboard = device.model else {
                receive(.disconnected)
                receive(.problem("This keyboard model is not supported.", blocking: true))
                return
            }
            let identity = try? LayoutIdentity(serial: device.serial, keyboard: keyboard)
            session.connect(identity: identity)
            connected = true; identityVerified = identity != nil
            connectedKeyboardName = device.displayName; connectedKeyboardModel = keyboard
            installedRevision = identity?.revisionID; currentLayer = nil; protocolVersion = nil
            liveLayers = [:]; blockingProblem = nil; layoutFailure = nil
            status = "Connecting to \(device.displayName)"
            connectionDetail = ""
            loadInstalled()
        case .identity(let identity):
            guard session.connected, identity.keyboard == connectedKeyboardModel else { return }
            let changed = session.identity != identity
            session.identify(identity)
            identityVerified = true; installedRevision = identity.revisionID
            if changed { resetTypingLayerHold(); installedTask?.cancel(); liveLayers = [:]; loadInstalled() }
        case .layer(let layer):
            let wasBlocked = blockingProblem != nil
            guard session.setLayer(layer) || wasBlocked else { return }
            blockingProblem = nil
            currentLayer = layer
            updateConnectedStatus()
        case .protocolVersion(let version): protocolVersion = version
        case .disconnected:
            resetTypingLayerHold()
            installedTask?.cancel(); installedTask = nil
            session.disconnect(); liveLayers = [:]
            connected = false; identityVerified = false; installedRevision = nil; currentLayer = nil; protocolVersion = nil
            connectedKeyboardName = nil; connectedKeyboardModel = nil
            blockingProblem = nil; layoutFailure = nil
            status = isPaused ? "Keyfinder is paused" : "Waiting for your keyboard"
            connectionDetail = ""
        case .problem(let message, let blocking):
            if blocking { blockingProblem = message }
            status = "Connection needs attention"; connectionDetail = message
        }
        synchronizeOverlay(); onStatusChange?()
    }

    private func loadInstalled() {
        layoutFailure = nil
        guard let lease = session.lease else {
            status = "Layout not identified"
            layoutFailure = "The installed Oryx revision is unknown. Retry, or select a specific saved revision in Layout settings."
            connectionDetail = layoutFailure!
            return
        }
        installedTask = Task { [weak self, repository] in
            do {
                let snapshot = try await repository.installed(lease.identity)
                guard !Task.isCancelled, let self, self.session.accept(snapshot, for: lease) else { return }
                self.layoutFailure = nil
                self.liveLayers = LabelResolver.prepare(snapshot)
                if (self.preferences.layoutURL.isEmpty || self.previewFollowsNextInstall) && !snapshot.isDemo {
                    self.previewFollowsNextInstall = false
                    self.previewInstalled(snapshot)
                }
                self.updateConnectedStatus()
                self.synchronizeOverlay(); self.onStatusChange?()
            } catch {
                guard !Task.isCancelled, let self, self.session.lease == lease else { return }
                self.layoutFailure = "The installed revision could not be loaded. \(error.localizedDescription)"
                self.connectionDetail = self.layoutFailure!
                self.status = "Layout unavailable"
                self.synchronizeOverlay(); self.onStatusChange?()
            }
        }
    }

    private func updateConnectedStatus() {
        guard session.connected else { return }
        guard blockingProblem == nil else { return }
        if let layoutFailure {
            status = session.identity == nil ? "Layout not identified" : "Layout unavailable"
            connectionDetail = layoutFailure
            return
        }
        if session.snapshot != nil {
            status = session.layer.map { $0 == 0 ? "Connected · typing layer" : "Connected · layer \($0)" } ?? "Connected · awaiting layer"
            connectionDetail = identityVerified ? "" : "Manually selected revision (unverified)"
        } else if session.identity != nil {
            status = "Loading installed layout"
        }
    }

    func setPreferences(_ value: Preferences) {
        let value = value.clamped()
        guard preferences != value else { return }
        let visibilityChanged = preferences.showMenuBarIcon != value.showMenuBarIcon
        let appearanceChanged = preferences.appearance != value.appearance
        let hotKeyChanged = preferences.typingLayerHotKey != value.typingLayerHotKey || preferences.typingLayerHotKeyEnabled != value.typingLayerHotKeyEnabled
        preferences = value; value.save(to: defaults)
        if hotKeyChanged { resetTypingLayerHold(); hotKey?.stop(); updateHotKeyRegistration() }
        if visibilityChanged { onMenuBarVisibilityChange?(value.showMenuBarIcon) }
        if appearanceChanged { onAppearanceChange?(value.appearance) }
        synchronizeOverlay()
    }
    func chooseLayer(_ index: Int) {
        previewLayerIndex = index; selectedKeyIndex = nil
        if isPreviewingOverlay || isArranging || isHoldingTypingLayer { synchronizeOverlay() }
    }
    var selectedPreview: PresentedLayer? { previewLayers[previewLayerIndex] }
    var previewOryxURL: URL? {
        guard let snapshot = previewSnapshot, !snapshot.isDemo else { return nil }
        return snapshot.identity.url
    }
    var selectedKey: PresentedKey? {
        guard let index = selectedKeyIndex, let layer = selectedPreview, layer.keys.indices.contains(index) else { return nil }
        return layer.keys[index]
    }

    func refreshLayout(url: String? = nil) {
        do {
            let text = url ?? preferences.layoutURL
            let location = try OryxLocation(url: text)
            previewTask?.cancel(); previewGeneration = UUID()
            let generation = previewGeneration
            var updated = preferences; updated.layoutURL = text
            setPreferences(updated)
            previewFollowsNextInstall = false
            isRefreshing = true; notice = nil
            previewTask = Task { [weak self, repository] in
                do {
                    let snapshot = try await repository.refresh(location)
                    guard !Task.isCancelled, let self, self.previewGeneration == generation else { return }
                    self.setPreview(snapshot)
                    self.notice = self.session.identity.map { identity in
                        if identity == snapshot.identity { return "The preview matches your installed revision." }
                        if identity.keyboard != snapshot.keyboard {
                            return "\(snapshot.keyboardName) preview updated. The live overlay still follows your \(identity.keyboard.displayName)."
                        }
                        return "Preview updated. The live overlay will use this revision after it is flashed to your keyboard."
                    } ?? "Preview updated."
                    self.isRefreshing = false
                    // A previously missing installed revision may now have been cached.
                    if self.session.identity == snapshot.identity { self.loadInstalled() }
                } catch {
                    guard !Task.isCancelled, let self, self.previewGeneration == generation else { return }
                    self.isRefreshing = false; self.notice = error.localizedDescription
                }
            }
        } catch { notice = error.localizedDescription }
    }

    private func previewInstalled(_ snapshot: LayoutSnapshot) {
        // A "latest" URL for the same layout still describes it; keep it for the next refresh.
        let location = try? OryxLocation(url: preferences.layoutURL)
        if location?.revisionID != nil || location?.keyboard != snapshot.keyboard || location?.layoutID != snapshot.layoutID {
            var preferences = self.preferences
            preferences.layoutURL = snapshot.identity.url.absoluteString
            setPreferences(preferences)
        }
        notice = nil
        setPreview(snapshot)
    }

    private func setPreview(_ snapshot: LayoutSnapshot) {
        guard let geometry = try? KeyboardGeometry.load(for: snapshot.keyboard) else {
            notice = "Could not load the \(snapshot.keyboardName) keyboard drawing."
            return
        }
        self.geometry = geometry
        previewSnapshot = snapshot; previewLayers = LabelResolver.prepare(snapshot)
        defaults.set("\(snapshot.layoutID)/\(snapshot.revisionID)", forKey: "previewIdentity")
        defaults.set(snapshot.keyboard.rawValue, forKey: "previewKeyboard")
        if previewLayers[previewLayerIndex] == nil { previewLayerIndex = snapshot.layers.first(where: { $0.position > 0 })?.position ?? 0 }
        selectedKeyIndex = nil
        if isPreviewingOverlay || isArranging || isHoldingTypingLayer { synchronizeOverlay() }
    }

    func importSnapshot(_ url: URL) {
        previewTask?.cancel(); previewGeneration = UUID(); previewFollowsNextInstall = false
        let generation = previewGeneration
        isRefreshing = true; notice = nil
        previewTask = Task { [weak self, repository] in
            do {
                let snapshot = try await repository.importSnapshot(from: url)
                guard !Task.isCancelled, let self, self.previewGeneration == generation else { return }
                if !snapshot.isDemo {
                    var preferences = self.preferences
                    preferences.layoutURL = snapshot.identity.url.absoluteString
                    self.setPreferences(preferences)
                }
                self.setPreview(snapshot); self.isRefreshing = false
                self.notice = "Imported revision \(snapshot.revisionID)."
                if self.session.identity == snapshot.identity { self.loadInstalled() }
            } catch {
                guard !Task.isCancelled, let self, self.previewGeneration == generation else { return }
                self.isRefreshing = false; self.notice = error.localizedDescription
            }
        }
    }

    func exportSnapshot(_ url: URL) {
        guard let snapshot = previewSnapshot else { return }
        Task {
            do {
                try await Task.detached(priority: .userInitiated) { try LayoutRepository.export(snapshot, to: url) }.value
                notice = "Snapshot exported."
            } catch { notice = error.localizedDescription }
        }
    }

    func usePreviewForUnidentifiedKeyboard() {
        guard session.connected, !identityVerified, let snapshot = previewSnapshot, !snapshot.isDemo, snapshot.keyboard == connectedKeyboardModel else { return }
        session.identify(snapshot.identity); installedRevision = snapshot.revisionID
        loadInstalled()
    }

    func togglePause() {
        guard !isFlashingFirmware else { return }
        isPaused.toggle()
        resetTypingLayerHold()
        isPreviewingOverlay = false; isArranging = false
        if isPaused { monitor.stop(); overlay.hide() }
        else {
            status = "Waiting for your keyboard"
            connectionDetail = ""
            if !suspended { monitor.start() }
        }
        updateHotKeyRegistration()
        onStatusChange?()
    }
    func retryConnection() {
        guard running, !isPaused, !suspended, !isFlashingFirmware else { return }
        monitor.reconnect()
    }
    func showOverlayPreview(arrange: Bool = false) {
        guard !isFlashingFirmware else { return }
        resetTypingLayerHold()
        isPreviewingOverlay = true; isArranging = arrange; synchronizeOverlay()
    }
    func endOverlayPreview() {
        resetTypingLayerHold()
        isPreviewingOverlay = false; isArranging = false; synchronizeOverlay()
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { notice = "Allow Keyfinder in System Settings → General → Login Items." }
        } catch { notice = "Could not change launch at login: \(error.localizedDescription)" }
    }

    private func synchronizeOverlay() {
        if suspended || isFlashingFirmware { overlay.hide() }
        else if isHoldingTypingLayer {
            let failure = connected ? blockingProblem ?? layoutFailure : nil
            let layer = connected ? (failure == nil ? liveLayers[0] : nil) : previewLayers[0]
            overlay.show(layer, message: failure ?? "Loading the installed typing layer…", preferences: preferences,
                         preview: !connected, unverified: connected && !identityVerified,
                         keyboard: connectedKeyboardModel ?? previewSnapshot?.keyboard, immediate: true)
        } else if isPreviewingOverlay || isArranging {
            overlay.show(selectedPreview, preferences: preferences, preview: true, arranging: isArranging)
        } else if !isPaused, session.shouldShowOverlay {
            if let blockingProblem { overlay.show(nil, message: blockingProblem, preferences: preferences, keyboard: connectedKeyboardModel) }
            else if let layoutFailure { overlay.show(nil, message: layoutFailure, preferences: preferences, keyboard: connectedKeyboardModel) }
            else if let layer = session.layer, let prepared = liveLayers[layer] { overlay.show(prepared, preferences: preferences, unverified: !identityVerified) }
            else {
                let text = session.snapshot == nil ? "Loading the installed layout. If it cannot be loaded, open Keyfinder settings to retry or import a snapshot." : "This layer is missing from the installed layout. Open Keyfinder settings to check the revision."
                overlay.show(nil, message: text, preferences: preferences, keyboard: connectedKeyboardModel)
            }
        } else { overlay.hide() }
    }

    var canStartFirmwareFlash: Bool { running && !suspended && !isFlashingFirmware }
    func flashFirmware() {
        guard canStartFirmwareFlash else { return }
        firmware.flash(keyboardName: connectedKeyboardName)
    }
    private func setFlashingFirmware(_ active: Bool) {
        if active {
            resetTypingLayerHold()
            // Clear the old revision before suppressing disconnected callbacks.
            receive(.disconnected)
            isFlashingFirmware = true
            previewFollowsNextInstall = false
            suspend()
            status = "Flashing keyboard firmware"
            connectionDetail = ""
        } else {
            isFlashingFirmware = false
            previewFollowsNextInstall = firmware.state == .succeeded
            receive(.disconnected)
            if running && !suspended && !isPaused { monitor.start() }
            updateHotKeyRegistration()
        }
        onStatusChange?()
    }
}
