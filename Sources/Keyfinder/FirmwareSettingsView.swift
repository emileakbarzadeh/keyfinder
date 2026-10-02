import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FirmwareSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var firmware: FirmwareFlasher
    @State private var isTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsSection("Flash keyboard firmware") {
                    Text("Download the compiled firmware from Oryx, then choose it here. Use the file for your keyboard model.")
                        .foregroundStyle(Color(nsColor: Theme.mutedText))
                    VStack(spacing: 12) {
                        Image(systemName: firmware.image == nil ? "arrow.down.document" : "doc.badge.gearshape")
                            .font(.system(size: 32, weight: .light)).foregroundStyle(Color(nsColor: Theme.accentText))
                        if let image = firmware.image {
                            Text(image.name).font(.headline).lineLimit(2).textSelection(.enabled)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(image.size), countStyle: .file))
                                .font(.caption).foregroundStyle(Color(nsColor: Theme.mutedText))
                        } else {
                            Text(firmware.state == .preparing ? "Reading firmware…" : "Drop a .bin file here").font(.headline)
                        }
                        HStack {
                            Button(firmware.image == nil ? "Choose file…" : "Choose another file…", action: chooseFile)
                            if firmware.image != nil { Button("Remove") { firmware.clear() } }
                        }.disabled(firmware.isBusy)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 26).padding(.horizontal, 16)
                    .background(Color(nsColor: Theme.background).opacity(isTargeted ? 0.5 : 1), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: isTargeted ? Theme.orange : Theme.border), style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [6, 5])))
                    .dropDestination(for: URL.self) { urls, _ in
                        guard !firmware.isFlashing else { return false }
                        firmware.select(urls); return true
                    } isTargeted: { isTargeted = $0 && !firmware.isFlashing }
                    .accessibilityElement(children: .contain).accessibilityLabel("Firmware file")

                    if let image = firmware.image {
                        DisclosureGroup("File checksum") {
                            Text("SHA-256: \(image.sha256)").font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.font(.caption)
                    }
                    if !firmware.backendAvailable {
                        Label("Zapp is missing from this build. Reinstall Keyfinder. For a source build, run it from nix develop.", systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(Color(nsColor: Theme.accentText))
                    }
                    Text("Flashing replaces the keyboard’s firmware. Connect only the keyboard you want to update. Keep your Mac awake and the keyboard plugged in until Zapp finishes.")
                        .font(.callout).foregroundStyle(Color(nsColor: Theme.mutedText))
                    HStack {
                        Label(firmware.targetName ?? model.connectedKeyboardName ?? "Connect your keyboard by USB", systemImage: "cable.connector")
                            .font(.callout).foregroundStyle(Color(nsColor: Theme.mutedText))
                        Spacer()
                        Button(firmware.isFlashing ? "Flashing…" : "Flash keyboard") { model.flashFirmware() }
                            .disabled(!firmware.canFlash || !model.canStartFirmwareFlash)
                    }
                    if let message = firmware.message {
                        Label(message, systemImage: firmware.state == .succeeded ? "checkmark.circle" : "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(Color(nsColor: firmware.state == .failed || firmware.image == nil ? Theme.accentText : Theme.text))
                            .textSelection(.enabled)
                    }
                }
                if firmware.isFlashing || !firmware.output.isEmpty {
                    SettingsSection("Zapp output") {
                        if firmware.isFlashing {
                            HStack(spacing: 12) {
                                ProgressView().controlSize(.small)
                                Text("When Zapp is waiting for bootloader mode, press your keyboard’s reset button to start flashing.")
                                    .font(.callout)
                            }
                            Text("The overlay is paused. You can close Settings; Keyfinder will stay open until flashing finishes.")
                                .font(.caption).foregroundStyle(Color(nsColor: Theme.mutedText))
                        }
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(firmware.output.isEmpty ? "Starting Zapp…" : firmware.output)
                                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    Color.clear.frame(height: 1).id("output-end")
                                }
                            }.onChange(of: firmware.output) { _, _ in proxy.scrollTo("output-end", anchor: .bottom) }
                        }.frame(height: 190)
                            .background(Color(nsColor: Theme.background), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                Text("Powered by ZSA’s Zapp. File selection and flashing require no Accessibility, Input Monitoring, or Screen Recording access.")
                    .font(.caption).foregroundStyle(Color(nsColor: Theme.mutedText))
            }.frame(maxWidth: 800).padding(.horizontal, 24).padding(.vertical, 8).frame(maxWidth: .infinity)
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "bin") ?? .data]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.message = "Choose the .bin firmware downloaded for your keyboard."
        panel.begin { response in
            if response == .OK, let url = panel.url { firmware.select([url]) }
        }
    }
}
