import AppKit
import SwiftUI
import UniformTypeIdentifiers
import KeyfinderCore

enum SettingsPage: String, CaseIterable { case keyboard = "Keyboard", appearance = "Appearance", connection = "Layout & connection" }

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var urlText = ""
    @State private var page: SettingsPage
    init(model: AppModel, initialPage: SettingsPage = .keyboard) {
        self.model = model; _page = State(initialValue: initialPage)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: "keyboard").font(.system(size: 26, weight: .medium)).foregroundStyle(.teal)
                    .frame(width: 52, height: 52).background(.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keyfinder").font(.title2.weight(.semibold))
                    Text("Your layers, at a glance.").foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 6) {
                        Circle().fill(model.connected && !model.isPaused ? Color.teal : Color.secondary).frame(width: 7, height: 7)
                        Text(model.status).font(.callout)
                    }
                    Text("Hidden on layer 0").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 25).padding(.vertical, 19)
            Divider()
            Picker("Settings", selection: $page) {
                ForEach(SettingsPage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 28).padding(.top, 16)
            Group {
                switch page {
                case .keyboard: keyboardTab
                case .appearance: appearanceTab
                case .connection: connectionTab
                }
            }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 920, minHeight: 780)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.teal)
        .onAppear { urlText = model.preferences.layoutURL }
    }

    private var keyboardTab: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Picker("Layer", selection: Binding(get: { model.previewLayerIndex }, set: model.chooseLayer)) {
                    ForEach(model.previewSnapshot?.layers ?? [], id: \.position) { layer in Text(layer.displayName).tag(layer.position) }
                }.pickerStyle(.segmented).frame(maxWidth: 450)
                Spacer()
                if model.isPreviewingOverlay {
                    Button(model.isArranging ? "Done arranging" : "Hide preview") { model.endOverlayPreview() }
                } else {
                    Button("Show overlay preview") { model.showOverlayPreview() }
                }
            }
            KeyboardPreview(model: model)
                .aspectRatio(920 / KeyboardView.height(forWidth: 920), contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 510)
            VStack(alignment: .leading, spacing: 7) {
                Text(model.selectedKey == nil ? "Explore your layout" : "Key details").font(.headline)
                ScrollView {
                    Text(model.selectedKey?.detail ?? "Click a key to see its tap, hold, and inherited actions. This preview is available even when your Moonlander is unplugged.")
                        .font(.callout).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 76)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Text("\(model.previewSnapshot?.title ?? "Moonlander") · revision \(model.previewSnapshot?.revisionID ?? "—")")
                Spacer()
                Text("Preview does not change your keyboard")
            }.font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }.padding(12)
    }

    private var appearanceTab: some View {
        Form {
            Section("Application") {
                Toggle("Show menu bar icon", isOn: preference(\.showMenuBarIcon))
                Text("When the icon is hidden, open Keyfinder from Applications or Spotlight to return to Settings. The overlay keeps working.").font(.caption).foregroundStyle(.secondary)
                Toggle("Launch Keyfinder at login", isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                Button("Quit Keyfinder") { NSApp.terminate(nil) }
            }
            Section("Overlay") {
                HStack { Text("Width"); Slider(value: preference(\.width), in: 620...1500, step: 10); Text("\(Int(model.preferences.width)) pt").monospacedDigit().frame(width: 65) }
                HStack { Text("Opacity"); Slider(value: preference(\.opacity), in: 0.4...1); Text("\(Int(model.preferences.opacity * 100))%").monospacedDigit().frame(width: 65) }
                Toggle("Use Oryx key colors", isOn: preference(\.useKeyColors))
                Picker("Appearance delay", selection: preference(\.appearanceDelay)) {
                    Text("Immediately").tag(0.0); Text("100 ms").tag(0.1); Text("200 ms").tag(0.2); Text("300 ms").tag(0.3)
                }
                Text("A short delay can hide brief layer changes. Returning to layer 0 always hides the overlay immediately.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Position") {
                Picker("Display", selection: preference(\.screenID)) {
                    Text("Main display").tag(UInt32(0))
                    ForEach(NSScreen.screens, id: \.displayID) { screen in Text(screen.localizedName).tag(screen.displayID) }
                }
                HStack {
                    ForEach([("Top left", 0.0, 1.0), ("Top center", 0.5, 1.0), ("Top right", 1.0, 1.0)], id: \.0) { title, x, y in
                        Button(title) { place(x: x, y: y) }.frame(maxWidth: .infinity)
                    }
                }
                HStack {
                    ForEach([("Bottom left", 0.0, 0.0), ("Bottom center", 0.5, 0.0), ("Bottom right", 1.0, 0.0)], id: \.0) { title, x, y in
                        Button(title) { place(x: x, y: y) }.frame(maxWidth: .infinity)
                    }
                }
                Button(model.isArranging ? "Done arranging" : "Drag overlay into place…") {
                    if model.isArranging { model.endOverlayPreview() } else { model.showOverlayPreview(arrange: true) }
                }
                Text("The live overlay passes clicks through to your apps. Dragging is enabled only while arranging.").font(.caption).foregroundStyle(.secondary)
                Button("Restore appearance defaults") {
                    var value = Preferences()
                    value.layoutURL = model.preferences.layoutURL
                    value.showMenuBarIcon = model.preferences.showMenuBarIcon
                    model.setPreferences(value)
                }
            }
        }.formStyle(.grouped)
    }

    private var connectionTab: some View {
        Form {
            Section("Moonlander") {
                LabeledContent("Status", value: model.status)
                if let layer = model.currentLayer { LabeledContent("Active layer", value: "\(layer)") }
                if let revision = model.installedRevision { LabeledContent("Installed revision", value: revision) }
                if let version = model.protocolVersion { LabeledContent("Oryx protocol", value: "\(version)") }
                Text(model.connectionDetail).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Button("Retry connection") { model.retryConnection() }.disabled(model.isPaused)
                    Button(model.isPaused ? "Resume monitoring" : "Pause monitoring") { model.togglePause() }
                    Button("Input Monitoring settings…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                    }
                }
                if model.connected && !model.identityVerified {
                    Button("Use preview revision for this keyboard (unverified)") { model.usePreviewForUnidentifiedKeyboard() }
                }
            }
            Section("Oryx layout") {
                TextField("Layout URL", text: $urlText).textFieldStyle(.roundedBorder)
                HStack {
                    Button(model.isRefreshing ? "Loading…" : "Load / refresh preview") { model.refreshLayout(url: urlText) }.disabled(model.isRefreshing)
                    Button("Open in Oryx") {
                        if let identity = model.previewSnapshot?.identity { NSWorkspace.shared.open(identity.url) }
                    }
                    Spacer()
                    Button("Import snapshot…", action: importFile)
                    Button("Export snapshot…", action: exportFile).disabled(model.previewSnapshot == nil)
                }
                if let notice = model.notice { Text(notice).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                Text("The live overlay follows the revision installed on your keyboard. After flashing in Oryx, it updates when the keyboard reconnects. Refreshing here changes the preview.").font(.callout).foregroundStyle(.secondary)
            }
            Section("Performance") {
                Text("No polling, scheduled refreshes, or continuous rendering. Keyfinder waits for USB and system notifications. Cached layouts work offline.").foregroundStyle(.secondary)
                Text("Oryx also sends physical key reports while connected. Keyfinder discards them immediately; it does not record or analyze your typing.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private func preference<T>(_ keyPath: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { model.preferences[keyPath: keyPath] }, set: { value in
            var preferences = model.preferences; preferences[keyPath: keyPath] = value; model.setPreferences(preferences)
        })
    }
    private func place(x: Double, y: Double) {
        var preferences = model.preferences; preferences.horizontalPosition = x; preferences.verticalPosition = y
        model.setPreferences(preferences); model.showOverlayPreview()
    }
    private func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.message = "Choose a Keyfinder layout snapshot."
        panel.begin { response in
            if response == .OK, let url = panel.url { model.importSnapshot(url) }
        }
    }
    private func exportFile() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Keyfinder-\(model.previewSnapshot?.revisionID ?? "layout").json"
        panel.begin { response in
            if response == .OK, let url = panel.url { model.exportSnapshot(url) }
        }
    }
}

struct KeyboardPreview: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeNSView(context: Context) -> KeyboardView {
        let view = KeyboardView(geometry: model.geometry)
        view.preview = true
        view.onSelect = { model.selectedKeyIndex = $0 }
        return view
    }
    func updateNSView(_ view: KeyboardView, context: Context) {
        view.presentedLayer = model.selectedPreview
        if view.useKeyColors != model.preferences.useKeyColors { view.useKeyColors = model.preferences.useKeyColors }
        if view.selectedIndex != model.selectedKeyIndex { view.selectedIndex = model.selectedKeyIndex }
    }
}
