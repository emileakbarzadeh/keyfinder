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
                Image(systemName: "keyboard").font(.system(size: 26, weight: .medium)).foregroundStyle(Color(nsColor: Theme.ink))
                    .frame(width: 52, height: 52).background(Color(nsColor: Theme.orange), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keyfinder").font(.title2.weight(.semibold))
                    Text(model.connectedKeyboardName.map { "\($0) layer overlay" } ?? "Keyboard layer overlay").foregroundStyle(Color(nsColor: Theme.mutedText))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 6) {
                        Circle().fill(model.connected && !model.isPaused ? Color(nsColor: Theme.orange) : Color(nsColor: Theme.mutedText)).frame(width: 7, height: 7)
                        Text(model.status).font(.callout)
                    }
                    Text("Hidden on layer 0").font(.caption).foregroundStyle(Color(nsColor: Theme.mutedText))
                }
            }.padding(.horizontal, 25).padding(.vertical, 19)
            Divider()
            PalettePicker(label: "Settings", options: SettingsPage.allCases.map { ($0, $0.rawValue) }, selection: $page)
                .frame(maxWidth: 520).padding(.horizontal, 28).padding(.top, 16)
            Group {
                switch page {
                case .keyboard: keyboardTab
                case .appearance: appearanceTab
                case .connection: connectionTab
                }
            }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 920, minHeight: 780)
        .background(Color(nsColor: Theme.background))
        .foregroundStyle(Color(nsColor: Theme.text))
        .tint(Color(nsColor: Theme.orange))
        .buttonStyle(PaletteButtonStyle())
        .toggleStyle(.switch)
        .preferredColorScheme(model.preferences.appearance.colorScheme)
        .onAppear { urlText = model.preferences.layoutURL }
        .onChange(of: model.preferences.layoutURL) { oldValue, newValue in
            if urlText == oldValue { urlText = newValue }
        }
    }

    private var keyboardTab: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                PalettePicker(label: "Layer", options: (model.previewSnapshot?.layers ?? []).map { ($0.position, $0.displayName) },
                              selection: Binding(get: { model.previewLayerIndex }, set: model.chooseLayer)).frame(maxWidth: 450)
                Spacer()
                if model.isPreviewingOverlay {
                    Button(model.isArranging ? "Done arranging" : "Hide preview") { model.endOverlayPreview() }
                } else {
                    Button("Show overlay preview") { model.showOverlayPreview() }
                }
            }
            KeyboardPreview(model: model)
                .aspectRatio(920 / KeyboardView.height(forWidth: 920, geometry: model.geometry), contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 510)
            VStack(alignment: .leading, spacing: 7) {
                Text(model.selectedKey == nil ? "Explore your layout" : "Key details").font(.headline)
                ScrollView {
                    Text(model.selectedKey?.detail ?? "Click a key to see its tap, hold, and inherited actions. This preview is available even when your keyboard is unplugged.")
                        .font(.callout).foregroundStyle(Color(nsColor: Theme.mutedText)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 76)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: Theme.surface), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Text(model.previewSnapshot?.isDemo == true ? "Keyfinder Demo · offline example" : "\(model.previewSnapshot?.title ?? "Keyboard") · revision \(model.previewSnapshot?.revisionID ?? "—")")
                Spacer()
                Text("Preview does not change your keyboard")
            }.font(.caption).foregroundStyle(Color(nsColor: Theme.mutedText))
            Spacer(minLength: 0)
        }.padding(12)
    }

    private var appearanceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsSection("Color theme") {
                    PalettePicker(label: "Color theme", options: AppAppearance.allCases.map { ($0, $0.title) },
                                  selection: preference(\.appearance))
                        .frame(maxWidth: 330)
                    Text("System follows macOS. The theme applies to Settings and the overlay.")
                        .font(.caption).foregroundStyle(Color(nsColor: Theme.mutedText))
                }
                SettingsSection("Application") {
                    switchRow("Show menu bar icon", isOn: preference(\.showMenuBarIcon))
                    Text("When the icon is hidden, open Keyfinder from Applications or Spotlight to return to Settings. The overlay keeps working.").font(.caption).foregroundStyle(Color(nsColor: Theme.mutedText))
                    switchRow("Launch Keyfinder at login", isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                    Button("Quit Keyfinder") { NSApp.terminate(nil) }
                }
                SettingsSection("Overlay") {
                    HStack { Text("Width").frame(width: 65, alignment: .leading); Slider(value: preference(\.width), in: 620...1500, step: 10); Text("\(Int(model.preferences.width)) pt").monospacedDigit().frame(width: 65) }
                    HStack { Text("Opacity").frame(width: 65, alignment: .leading); Slider(value: preference(\.opacity), in: 0.4...1); Text("\(Int(model.preferences.opacity * 100))%").monospacedDigit().frame(width: 65) }
                    switchRow("Use Oryx key colors", isOn: preference(\.useKeyColors))
                    HStack {
                        Text("Appearance delay"); Spacer()
                        Picker("Appearance delay", selection: preference(\.appearanceDelay)) {
                            Text("Immediately").tag(0.0); Text("100 ms").tag(0.1); Text("200 ms").tag(0.2); Text("300 ms").tag(0.3)
                        }.labelsHidden()
                    }
                    Text("A short delay can hide brief layer changes. Returning to layer 0 always hides the overlay immediately.").font(.caption).foregroundStyle(Color(nsColor: Theme.mutedText))
                }
                SettingsSection("Position") {
                    HStack {
                        Text("Display"); Spacer()
                        Picker("Display", selection: preference(\.screenID)) {
                            Text("Main display").tag(UInt32(0))
                            ForEach(NSScreen.screens, id: \.displayID) { screen in Text(screen.localizedName).tag(screen.displayID) }
                        }.labelsHidden()
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
                    Text("The live overlay passes clicks through to your apps. Dragging is enabled only while arranging.").font(.caption).foregroundStyle(Color(nsColor: Theme.mutedText))
                    Button("Restore appearance defaults") {
                        var value = Preferences()
                        value.layoutURL = model.preferences.layoutURL
                        value.showMenuBarIcon = model.preferences.showMenuBarIcon
                        model.setPreferences(value)
                    }
                }
            }.frame(maxWidth: 800).padding(.horizontal, 24).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
        }
    }

    private var connectionTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsSection(model.connectedKeyboardName ?? "Keyboard") {
                    LabeledContent("Status", value: model.status)
                    if let layer = model.currentLayer { LabeledContent("Active layer", value: "\(layer)") }
                    if let revision = model.installedRevision { LabeledContent("Installed revision", value: revision) }
                    if let version = model.protocolVersion { LabeledContent("Oryx protocol", value: "\(version)") }
                    Text(model.connectionDetail).foregroundStyle(Color(nsColor: Theme.mutedText)).textSelection(.enabled)
                    Text("Supported keyboards: " + KeyboardModel.allCases.map(\.displayName).joined(separator: ", "))
                        .font(.caption).foregroundStyle(Color(nsColor: Theme.mutedText))
                    HStack {
                        Button("Retry connection") { model.retryConnection() }.disabled(model.isPaused)
                        Button(model.isPaused ? "Resume monitoring" : "Pause monitoring") { model.togglePause() }
                        Button("Input Monitoring settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                        }
                    }
                    if model.connected && !model.identityVerified {
                        Button("Use preview revision for this keyboard (unverified)") { model.usePreviewForUnidentifiedKeyboard() }
                            .disabled(model.previewSnapshot?.isDemo != false || model.previewSnapshot?.keyboard != model.connectedKeyboardModel)
                    }
                }
                SettingsSection("Oryx layout") {
                    TextField("Layout URL", text: $urlText, prompt: Text("Paste a keyboard layout URL from Oryx")).textFieldStyle(.roundedBorder)
                    HStack {
                        Button(model.isRefreshing ? "Loading…" : "Load / refresh preview") { model.refreshLayout(url: urlText) }
                            .disabled(model.isRefreshing || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Open in Oryx") {
                            if let url = model.previewOryxURL { NSWorkspace.shared.open(url) }
                        }.disabled(model.previewOryxURL == nil)
                        Spacer()
                        Button("Import snapshot…", action: importFile)
                        Button("Export snapshot…", action: exportFile).disabled(model.previewSnapshot == nil)
                    }
                    if let notice = model.notice { Text(notice).font(.callout).foregroundStyle(Color(nsColor: Theme.mutedText)).textSelection(.enabled) }
                    if model.previewSnapshot?.isDemo == true {
                        Text("This offline demo is a synthetic example. Connect your keyboard, paste an Oryx URL, or import a snapshot to use a real layout.").font(.callout).foregroundStyle(Color(nsColor: Theme.mutedText))
                    }
                    Text("The live overlay follows the revision installed on your keyboard. After flashing in Oryx, it updates when the keyboard reconnects. Refreshing here changes the preview.").font(.callout).foregroundStyle(Color(nsColor: Theme.mutedText))
                }
                SettingsSection("Performance") {
                    Text("No polling, scheduled refreshes, or continuous rendering. Keyfinder waits for USB and system notifications. Cached layouts work offline.").foregroundStyle(Color(nsColor: Theme.mutedText))
                    Text("Oryx also sends physical key reports while connected. Keyfinder discards them immediately; it does not record or analyze your typing.").font(.caption).foregroundStyle(Color(nsColor: Theme.mutedText))
                }
            }.frame(maxWidth: 800).padding(.horizontal, 24).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
        }
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title); Spacer()
            Toggle(title, isOn: isOn).labelsHidden()
        }
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
        if view.geometry != model.geometry { view.geometry = model.geometry }
        view.presentedLayer = model.selectedPreview
        if view.useKeyColors != model.preferences.useKeyColors { view.useKeyColors = model.preferences.useKeyColors }
        if view.selectedIndex != model.selectedKeyIndex { view.selectedIndex = model.selectedKeyIndex }
    }
}

private struct PaletteButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(nsColor: Theme.text))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color(nsColor: configuration.isPressed ? Theme.key : Theme.surface), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(nsColor: Theme.border), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}

private struct PalettePicker<Value: Hashable>: View {
    let label: String
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.0) { value, title in
                Button { selection = value } label: {
                    Text(title).font(.callout.weight(selection == value ? .semibold : .regular))
                        .foregroundStyle(Color(nsColor: selection == value ? Theme.ink : Theme.text))
                        .lineLimit(1).frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(selection == value ? Color(nsColor: Theme.orange) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selection == value ? [.isSelected] : [])
            }
        }.padding(3).background(Color(nsColor: Theme.surface), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain).accessibilityLabel(label)
            .onMoveCommand { direction in
                guard let index = options.firstIndex(where: { $0.0 == selection }) else { return }
                let step = direction == .left ? -1 : direction == .right ? 1 : 0
                let next = index + step
                if options.indices.contains(next) { selection = options[next].0 }
            }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: Theme.surface), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
