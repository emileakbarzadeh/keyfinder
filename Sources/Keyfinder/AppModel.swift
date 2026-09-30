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
    @Published private(set) var status = "Waiting for your Moonlander"
    @Published private(set) var connectionDetail = "Connect your keyboard when you’re ready. Preview works offline."
    @Published private(set) var notice: String?
    @Published private(set) var isPaused = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isPreviewingOverlay = false
    @Published private(set) var isArranging = false
    @Published private(set) var connected = false
    @Published private(set) var installedRevision: String?
    @Published private(set) var currentLayer: Int?
    @Published private(set) var identityVerified = false
    @Published private(set) var protocolVersion: Int?
    @Published private(set) var launchAtLogin = false
    let geometry: [KeyGeometry]
    let overlay: OverlayController
    private let monitor: any KeyboardMonitoring
    private let repository: LayoutRepository
    private let defaults: UserDefaults
    private var session = LiveSession()
    private var liveLayers: [Int: PresentedLayer] = [:]
    private var installedTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var previewGeneration = UUID()
    private var observers: [NSObjectProtocol] = []
    private var blockingProblem: String?
    private var layoutFailure: String?
    var onStatusChange: (() -> Void)?
    var onMenuBarVisibilityChange: ((Bool) -> Void)?

    init(geometry: [KeyGeometry], monitor: any KeyboardMonitoring, repository: LayoutRepository,
         defaults: UserDefaults = .standard, overlay: OverlayController) {
        self.geometry = geometry; self.monitor = monitor; self.repository = repository; self.defaults = defaults; self.overlay = overlay
        preferences = Preferences.load(from: defaults)
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
        monitor.start()
        if let serial = defaults.string(forKey: "previewIdentity"), let identity = try? LayoutIdentity(serial: serial) {
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
            MainActor.assumeIsolated { self?.suspend() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.isPaused == false { self?.monitor.start() } }
        })
    }

    func stop() {
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
        monitor.stop(); overlay.hide()
    }

    func receive(_ event: KeyboardEvent) {
        switch event {
        case .connected(let device):
            installedTask?.cancel()
            let identity = try? LayoutIdentity(serial: device.serial)
            session.connect(identity: identity)
            connected = true; identityVerified = identity != nil
            installedRevision = identity?.revisionID; currentLayer = nil; protocolVersion = nil
            liveLayers = [:]; blockingProblem = nil; layoutFailure = nil
            status = "Connecting to Moonlander"
            connectionDetail = identity.map { "Layout \($0.layoutID) · revision \($0.revisionID)" } ?? "Reading the installed Oryx revision…"
            loadInstalled()
        case .identity(let identity):
            guard session.connected else { return }
            let changed = session.identity != identity
            session.identify(identity)
            identityVerified = true; installedRevision = identity.revisionID
            if changed { installedTask?.cancel(); liveLayers = [:]; loadInstalled() }
        case .layer(let layer):
            let wasBlocked = blockingProblem != nil
            guard session.setLayer(layer) || wasBlocked else { return }
            blockingProblem = nil
            currentLayer = layer
            updateConnectedStatus()
        case .protocolVersion(let version): protocolVersion = version
        case .disconnected:
            installedTask?.cancel(); installedTask = nil
            session.disconnect(); liveLayers = [:]
            connected = false; identityVerified = false; installedRevision = nil; currentLayer = nil; protocolVersion = nil
            blockingProblem = nil; layoutFailure = nil
            status = isPaused ? "Keyfinder is paused" : "Waiting for your Moonlander"
            connectionDetail = isPaused ? "USB monitoring is stopped until you resume." : "Connect your keyboard when you’re ready. Preview works offline."
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
            connectionDetail = "Installed revision \(session.identity?.revisionID ?? "unknown")" + (identityVerified ? " · automatic sync" : " · manually selected, unverified")
        } else if session.identity != nil {
            status = "Loading installed layout"
        }
    }

    func setPreferences(_ value: Preferences) {
        let value = value.clamped()
        guard preferences != value else { return }
        let visibilityChanged = preferences.showMenuBarIcon != value.showMenuBarIcon
        preferences = value; value.save(to: defaults)
        if visibilityChanged { onMenuBarVisibilityChange?(value.showMenuBarIcon) }
        synchronizeOverlay()
    }
    func chooseLayer(_ index: Int) {
        previewLayerIndex = index; selectedKeyIndex = nil
        if isPreviewingOverlay || isArranging { synchronizeOverlay() }
    }
    var selectedPreview: PresentedLayer? { previewLayers[previewLayerIndex] }
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
            isRefreshing = true; notice = nil
            previewTask = Task { [weak self, repository] in
                do {
                    let snapshot = try await repository.refresh(location)
                    guard !Task.isCancelled, let self, self.previewGeneration == generation else { return }
                    self.setPreview(snapshot)
                    self.notice = self.session.identity.map { $0 == snapshot.identity ? "The preview matches your installed revision." : "Preview updated. The live overlay will use this revision after it is flashed to your keyboard." } ?? "Preview updated and saved for offline use."
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

    private func setPreview(_ snapshot: LayoutSnapshot) {
        previewSnapshot = snapshot; previewLayers = LabelResolver.prepare(snapshot)
        defaults.set("\(snapshot.layoutID)/\(snapshot.revisionID)", forKey: "previewIdentity")
        if previewLayers[previewLayerIndex] == nil { previewLayerIndex = snapshot.layers.first(where: { $0.position > 0 })?.position ?? 0 }
        selectedKeyIndex = nil
        if isPreviewingOverlay || isArranging { synchronizeOverlay() }
    }

    func importSnapshot(_ url: URL) {
        previewTask?.cancel(); previewGeneration = UUID()
        let generation = previewGeneration
        isRefreshing = true; notice = nil
        previewTask = Task { [weak self, repository] in
            do {
                let snapshot = try await repository.importSnapshot(from: url)
                guard !Task.isCancelled, let self, self.previewGeneration == generation else { return }
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
        guard session.connected, !identityVerified, let snapshot = previewSnapshot else { return }
        session.identify(snapshot.identity); installedRevision = snapshot.revisionID
        loadInstalled()
    }

    func togglePause() {
        isPaused.toggle()
        isPreviewingOverlay = false; isArranging = false
        if isPaused { monitor.stop(); overlay.hide() }
        else {
            status = "Waiting for your Moonlander"
            connectionDetail = "Connect your keyboard when you’re ready. Preview works offline."
            monitor.start()
        }
        onStatusChange?()
    }
    func retryConnection() {
        guard !isPaused else { return }
        monitor.reconnect()
    }
    func showOverlayPreview(arrange: Bool = false) {
        isPreviewingOverlay = true; isArranging = arrange; synchronizeOverlay()
    }
    func endOverlayPreview() {
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
        if isPreviewingOverlay || isArranging {
            overlay.show(selectedPreview, preferences: preferences, preview: true, arranging: isArranging)
        } else if !isPaused, session.shouldShowOverlay {
            if let blockingProblem { overlay.show(nil, message: blockingProblem, preferences: preferences) }
            else if let layoutFailure { overlay.show(nil, message: layoutFailure, preferences: preferences) }
            else if let layer = session.layer, let prepared = liveLayers[layer] { overlay.show(prepared, preferences: preferences, unverified: !identityVerified) }
            else {
                let text = session.snapshot == nil ? "Loading the installed layout. If it cannot be loaded, open Keyfinder settings to retry or import a snapshot." : "This layer is missing from the installed layout. Open Keyfinder settings to check the revision."
                overlay.show(nil, message: text, preferences: preferences)
            }
        } else { overlay.hide() }
    }
}
