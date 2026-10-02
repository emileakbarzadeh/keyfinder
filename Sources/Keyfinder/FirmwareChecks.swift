import AppKit
import SwiftUI
import KeyfinderCore

extension Diagnostics {
    static func checkFirmware(directory: URL, fixture: URL) async throws -> [String: Bool] {
        try verifyFirmwareFixture(fixture)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Keyfinder-flash-checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let suite = "io.keyfinder.firmware.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: temporary); defaults.removePersistentDomain(forName: suite) }
        var checks: [String: Bool] = [:]
        let original = Data("Keyfinder test fixture\nsuccess\n".utf8)
        let source = temporary.appendingPathComponent("firmware with spaces; $(unused).BIN")
        try original.write(to: source)
        let staged = try await Task.detached { try FirmwareImage.stage(source) }.value
        defer { staged.remove() }
        try Data("replaced".utf8).write(to: source)
        checks["reviewed_bytes_survive_download_replacement"] = try Data(contentsOf: staged.url) == original && staged.size == original.count
        checks["staging_preserves_firmware_filename"] = staged.url.lastPathComponent == source.lastPathComponent
        checks["checksum_covers_staged_bytes"] = staged.sha256 == "2c995b8b6960e1958763f589bff1d1cc599a2e413cfb664990157307355c7b50"
        func rejected(_ url: URL) -> Bool {
            do { let image = try FirmwareImage.stage(url); image.remove(); return false }
            catch { return true }
        }
        checks["non_file_urls_rejected"] = rejected(URL(string: "https://example.invalid/firmware.bin")!)
        checks["wrong_extension_rejected"] = rejected(temporary.appendingPathComponent("firmware.hex"))
        let empty = temporary.appendingPathComponent("empty.bin"); try Data().write(to: empty)
        checks["empty_file_rejected"] = rejected(empty)
        let folder = temporary.appendingPathComponent("folder.bin"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        checks["directory_rejected"] = rejected(folder)
        let link = temporary.appendingPathComponent("link.bin"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        checks["symlink_rejected"] = rejected(link)
        let large = temporary.appendingPathComponent("large.bin"); FileManager.default.createFile(atPath: large.path, contents: nil)
        let file = try FileHandle(forWritingTo: large); try file.truncate(atOffset: UInt64(FirmwareImage.maximumSize + 1)); try file.close()
        checks["oversized_file_rejected_before_reading"] = rejected(large)
        let pipe = temporary.appendingPathComponent("pipe.bin"); mkfifo(pipe.path, 0o600)
        checks["pipe_rejected_without_blocking"] = rejected(pipe)

        let runner = FixtureFlashRunner()
        let firmware = FirmwareFlasher(runner: runner)
        let keyboard = SimulatedKeyboard()
        let geometry = try KeyboardGeometry.load()
        let overlay = OverlayController(geometry: geometry)
        let model = AppModel(geometry: geometry, monitor: keyboard, repository: LayoutRepository(directory: temporary, client: FirmwareOfflineClient()),
                             defaults: defaults, overlay: overlay, firmware: firmware)
        model.start(observeSleep: false)
        defer { model.stop(); firmware.clear() }
        try original.write(to: source)
        firmware.select([source]); try await firmwareWait { !firmware.isBusy }
        checks["drop_stages_file_without_starting_backend"] = firmware.state == .ready && runner.starts == 0 && keyboard.running
        let reviewedURL = firmware.image?.url
        firmware.select([source, empty])
        checks["multiple_files_clear_previous_selection"] = firmware.image == nil && firmware.message != nil
            && reviewedURL.map { !FileManager.default.fileExists(atPath: $0.path) } == true
        firmware.select([source]); firmware.clear(); try await Task.sleep(for: .milliseconds(60))
        checks["late_file_read_cannot_restore_cleared_selection"] = firmware.image == nil && firmware.state == .empty
        firmware.select([source]); try await firmwareWait { !firmware.isBusy }

        // Capture real SwiftUI in both appearances with a simulated backend.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for mode in [AppAppearance.dark, .light] {
            var prefs = model.preferences; prefs.appearance = mode; model.setPreferences(prefs)
            let view = NSHostingView(rootView: SettingsView(model: model, initialPage: .firmware))
            view.frame = NSRect(x: 0, y: 0, width: 1000, height: 900)
            view.appearance = mode.appKit
            try capture(view, to: directory.appendingPathComponent("firmware\(mode == .light ? "-light" : "").png"))
        }

        keyboard.emit(.connected(ConnectedKeyboard(name: "Moonlander", serial: "keyfinder-demo/v1", productID: 0x1969)))
        model.showOverlayPreview()
        model.flashFirmware(); try await firmwareWait { runner.starts == 1 }
        checks["flash_releases_hid_and_hides_overlay"] = firmware.isFlashing && model.isFlashingFirmware && !keyboard.running && !overlay.panel.isVisible
        checks["reviewed_file_and_keyboard_name_retained"] = runner.file == firmware.image?.url && firmware.targetName == "Moonlander"
        for mode in [AppAppearance.dark, .light] {
            var prefs = model.preferences; prefs.appearance = mode; model.setPreferences(prefs)
            let view = NSHostingView(rootView: SettingsView(model: model, initialPage: .firmware))
            view.frame = NSRect(x: 0, y: 0, width: 1000, height: 900)
            view.appearance = mode.appKit
            try capture(view, to: directory.appendingPathComponent("firmware-waiting\(mode == .light ? "-light" : "").png"))
        }
        model.flashFirmware(); firmware.select([empty]); firmware.clear(); model.togglePause(); model.retryConnection(); model.showOverlayPreview()
        keyboard.emit(.connected(ConnectedKeyboard(name: "Voyager", serial: "keyfinder-demo/v1", productID: 0x1977)))
        checks["flash_blocks_duplicate_start_file_changes_and_usb_callbacks"] = runner.starts == 1 && firmware.image?.name == source.lastPathComponent
            && !keyboard.running && !model.connected && !model.isPaused && !overlay.panel.isVisible
        model.setSystemState(sleeping: true); model.setSystemState(sleeping: false)
        checks["wake_during_flash_does_not_reopen_hid"] = !keyboard.running
        runner.finish(ZappResult(status: 0, signalled: false)); try await firmwareWait { !model.isFlashingFirmware }
        checks["successful_flash_resumes_monitoring"] = firmware.state == .succeeded && keyboard.running && model.installedRevision == nil

        model.togglePause(); model.flashFirmware(); try await firmwareWait { runner.starts == 2 }
        runner.finish(ZappResult(status: 17, signalled: false)); try await firmwareWait { !model.isFlashingFirmware }
        checks["failure_preserves_user_pause_and_reports_exit_status"] = model.isPaused && !keyboard.running && firmware.state == .failed && firmware.message?.contains("17") == true
        model.togglePause(); model.flashFirmware(); try await firmwareWait { runner.starts == 3 }
        model.setSystemState(sessionActive: false)
        runner.finish(ZappResult(status: 0, signalled: false)); try await firmwareWait { !model.isFlashingFirmware }
        checks["completion_in_inactive_session_keeps_monitoring_stopped"] = !keyboard.running
        model.setSystemState(sessionActive: true)
        checks["return_to_active_session_resumes_monitoring"] = keyboard.running
        runner.failToLaunch = true; model.flashFirmware(); try await firmwareWait { !model.isFlashingFirmware }
        checks["launch_failure_resumes_monitoring_and_reports_error"] = keyboard.running && firmware.state == .failed && firmware.message?.contains("Fixture launch failure") == true
        runner.isAvailable = false
        checks["missing_backend_disables_flashing"] = !firmware.canFlash

        let native = ZappRunner(executable: fixture)
        var output = ""
        let result = try await native.flash(staged.url) { output += String(decoding: $0, as: UTF8.self) }
        checks["process_captures_stdout_and_stderr_before_success"] = result.succeeded && output.contains("stderr is captured") && output.contains("path=\(staged.url.path)")
        let special = temporary.appendingPathComponent("path with spaces; $(touch unwanted).bin")
        try original.write(to: special); output = ""
        let specialResult = try await native.flash(special) { output += String(decoding: $0, as: UTF8.self) }
        checks["process_passes_path_as_one_literal_argument"] = specialResult.succeeded && output.contains("path=\(special.path)")
        try Data("Keyfinder test fixture\nawait-output\n".utf8).write(to: special)
        let streaming = try await native.flash(special) { _ in
            try? Data().write(to: special.appendingPathExtension("ack"))
        }
        checks["short_prompts_arrive_before_process_exit"] = streaming.succeeded
        try Data("Keyfinder test fixture\nfailure\n".utf8).write(to: special)
        let failure = try await native.flash(special) { _ in }
        checks["process_preserves_nonzero_exit_code"] = failure.status == 23 && !failure.succeeded
        try Data("Keyfinder test fixture\nsignal\n".utf8).write(to: special)
        let signal = try await native.flash(special) { _ in }
        checks["process_signal_is_not_success"] = signal.signalled && !signal.succeeded
        try Data("Keyfinder test fixture\nlarge-output\n".utf8).write(to: special)
        var log = FirmwareLog()
        let noisy = try await native.flash(special) { log.append($0) }
        checks["large_process_output_is_drained_and_bounded"] = noisy.succeeded && log.truncated && log.text.utf8.count < FirmwareLog.limit + 100 && log.text.hasSuffix("final output\n")
        var unicode = FirmwareLog(); unicode.append(Data([0xE2, 0x86])); unicode.append(Data([0x92]))
        checks["split_utf8_output_is_preserved"] = unicode.text == "→"
        unicode.append(Data("\u{1B}[31mred\u{1B}[0m\rnext".utf8))
        checks["terminal_formatting_is_removed"] = unicode.text == "→red\nnext"
        do {
            _ = try await ZappRunner(executable: temporary.appendingPathComponent("missing-zapp")).flash(special) { _ in }
            checks["process_launch_failure_is_reported"] = false
        } catch { checks["process_launch_failure_is_reported"] = true }
        return checks
    }

    private static func firmwareWait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw FirmwareError("Firmware check timed out.")
    }

    private static func verifyFirmwareFixture(_ url: URL) throws {
        // Refuse a real Zapp supplied accidentally as the diagnostic argument.
        // The identity probe has no firmware path and never uses `flash`.
        guard url.lastPathComponent == "KeyfinderZappFixture" else {
            throw FirmwareError("Firmware checks require the built KeyfinderZappFixture executable, never the real Zapp.")
        }
        let process = Process(), pipe = Pipe()
        process.executableURL = url; process.arguments = ["--keyfinder-fixture"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run(); try? pipe.fileHandleForWriting.close()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit(); try? pipe.fileHandleForReading.close()
        guard process.terminationStatus == 0, String(decoding: data, as: UTF8.self) == "KeyfinderZappFixture v1 (no USB)\n" else {
            throw FirmwareError("The supplied executable is not the firmware test fixture.")
        }
    }
}

@MainActor private final class FixtureFlashRunner: ZappRunning {
    var isAvailable = true
    var available: Bool { isAvailable }
    var failToLaunch = false
    private(set) var starts = 0
    private(set) var file: URL?
    private var pending: CheckedContinuation<ZappResult, Error>?
    func flash(_ firmware: URL, output: @escaping @MainActor (Data) -> Void) async throws -> ZappResult {
        starts += 1; file = firmware
        if failToLaunch { throw FirmwareError("Fixture launch failure") }
        output(Data("Fixture: waiting for keyboard reset\n".utf8))
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func finish(_ result: ZappResult) { let completion = pending; pending = nil; completion?.resume(returning: result) }
}

private struct FirmwareOfflineClient: LayoutFetching {
    func fetch(keyboard: KeyboardModel, layoutID: String, revisionID: String) async throws -> LayoutSnapshot {
        throw FirmwareError("Offline firmware check")
    }
}
