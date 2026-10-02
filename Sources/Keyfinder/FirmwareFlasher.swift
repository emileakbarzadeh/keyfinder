import AppKit
import Combine
import CryptoKit
import Darwin

struct FirmwareImage: Sendable {
    static let maximumSize = 64 * 1024 * 1024
    let name: String
    let size: Int
    let sha256: String
    let directory: URL
    var url: URL { directory.appendingPathComponent(name) }

    // Copy once before review. Moving or replacing the download later must not
    // change the bytes passed to the flasher. Never memory-map the original.
    static func stage(_ source: URL) throws -> FirmwareImage {
        guard source.isFileURL, source.pathExtension.lowercased() == "bin" else {
            throw FirmwareError("Choose a .bin firmware file downloaded from Oryx.")
        }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let descriptor = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw FirmwareError("Could not open this file. Choose a local .bin file, not a link.") }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw FirmwareError("Choose a regular .bin file.")
        }
        guard info.st_size > 0, info.st_size <= maximumSize else {
            throw FirmwareError("Firmware must be nonempty and no larger than 64 MiB.")
        }
        let data = try file.read(upToCount: Int(info.st_size) + 1) ?? Data()
        guard !data.isEmpty, data.count <= maximumSize, data.count == info.st_size else {
            throw FirmwareError("The firmware file changed while being read. Choose it again.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Keyfinder-firmware-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let url = directory.appendingPathComponent(source.lastPathComponent)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: url.path)
            return FirmwareImage(name: source.lastPathComponent, size: data.count,
                                 sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), directory: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

struct FirmwareError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct ZappResult: Sendable {
    let status: Int32
    let signalled: Bool
    var succeeded: Bool { status == 0 && !signalled }
}

@MainActor protocol ZappRunning {
    var available: Bool { get }
    func flash(_ firmware: URL, output: @escaping @MainActor (Data) -> Void) async throws -> ZappResult
}

@MainActor final class ZappRunner: ZappRunning {
    private let executableOverride: URL?
    init(executable: URL? = nil) { executableOverride = executable }
    var available: Bool { executable != nil }

    private var executable: URL? {
        if let executableOverride { return executableOverride }
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/zapp")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        // SwiftPM development runs have no app bundle. A release must use its
        // bundled backend, never an unrelated command from a user's PATH.
        guard Bundle.main.bundleURL.pathExtension != "app" else { return nil }
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return paths.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0).appendingPathComponent("zapp") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    func flash(_ firmware: URL, output: @escaping @MainActor (Data) -> Void) async throws -> ZappResult {
        guard let executable else { throw FirmwareError("Zapp is missing. Reinstall Keyfinder, or use nix develop for a source build.") }
        // A dedicated worker drains the combined stream before collecting the
        // exit status. No shell, polling, event tap, or main-thread pipe reads.
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue(label: "io.keyfinder.zapp", qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = executable
                process.arguments = ["flash", firmware.path]
                process.currentDirectoryURL = firmware.deletingLastPathComponent()
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = pipe; process.standardError = pipe
                var environment = ProcessInfo.processInfo.environment
                environment["NO_COLOR"] = "1"; environment["TERM"] = "dumb"
                process.environment = environment
                do {
                    try process.run()
                    try? pipe.fileHandleForWriting.close()
                    // sync provides backpressure: at most one chunk is queued
                    // for the UI, even if the backend emits a large error log.
                    // FileHandle.read(upToCount:) can wait to fill its buffer
                    // on a pipe. A single read returns an available short
                    // prompt immediately, even while Zapp waits for reset.
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while true {
                        let count = buffer.withUnsafeMutableBytes {
                            Darwin.read(pipe.fileHandleForReading.fileDescriptor, $0.baseAddress, $0.count)
                        }
                        if count == 0 { break }
                        if count < 0 {
                            if errno == EINTR { continue }
                            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                        }
                        let chunk = Data(buffer.prefix(count))
                        DispatchQueue.main.sync { output(chunk) }
                    }
                    process.waitUntilExit()
                    try? pipe.fileHandleForReading.close()
                    continuation.resume(returning: ZappResult(status: process.terminationStatus, signalled: process.terminationReason == .uncaughtSignal))
                } catch {
                    try? pipe.fileHandleForWriting.close()
                    try? pipe.fileHandleForReading.close()
                    // A read error is not permission to terminate a writer.
                    if process.isRunning { process.waitUntilExit() }
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

struct FirmwareLog {
    static let limit = 32 * 1024
    private var bytes = Data()
    private(set) var truncated = false
    mutating func append(_ data: Data) {
        bytes.append(data)
        if bytes.count > Self.limit { bytes.removeFirst(bytes.count - Self.limit); truncated = true }
    }
    var text: String {
        let text = String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "\u{1B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return (truncated ? "Earlier output omitted.\n" : "") + text.filter { $0 == "\n" || $0 == "\t" || !$0.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) }
    }
}

@MainActor final class FirmwareFlasher: ObservableObject {
    enum State: Equatable { case empty, preparing, ready, flashing, succeeded, failed }
    @Published private(set) var state: State = .empty
    @Published private(set) var image: FirmwareImage?
    @Published private(set) var message: String?
    @Published private(set) var output = ""
    @Published private(set) var targetName: String?
    var onFlashingChange: ((Bool) -> Void)?
    private let runner: any ZappRunning
    private var log = FirmwareLog()
    private var selection = UUID()
    var isFlashing: Bool { state == .flashing }
    var isBusy: Bool { state == .preparing || isFlashing }
    var backendAvailable: Bool { runner.available }
    var canFlash: Bool { image != nil && !isBusy && backendAvailable }

    init(runner: any ZappRunning) { self.runner = runner }
    isolated deinit { image?.remove() }

    func select(_ urls: [URL]) {
        guard !isFlashing else { return }
        clear()
        guard urls.count == 1, let url = urls.first else {
            message = "Choose one firmware file at a time."; return
        }
        state = .preparing
        let generation = selection
        Task { [weak self] in
            do {
                let image = try await Task.detached(priority: .userInitiated) { try FirmwareImage.stage(url) }.value
                guard let self, self.selection == generation else { image.remove(); return }
                self.image = image; self.state = .ready
            } catch {
                guard let self, self.selection == generation else { return }
                self.state = .empty; self.message = error.localizedDescription
            }
        }
    }

    func clear() {
        guard !isFlashing else { return }
        selection = UUID(); image?.remove(); image = nil
        state = .empty; message = nil; targetName = nil; output = ""; log = FirmwareLog()
    }

    func flash(keyboardName: String?) {
        guard canFlash, let image else { return }
        targetName = keyboardName
        state = .flashing; message = nil; log = FirmwareLog(); output = ""
        onFlashingChange?(true)
        Task {
            let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled, .automaticTerminationDisabled, .suddenTerminationDisabled], reason: "Flashing keyboard firmware")
            defer { ProcessInfo.processInfo.endActivity(activity); onFlashingChange?(false) }
            do {
                let result = try await runner.flash(image.url) { [weak self] chunk in
                    guard let self else { return }
                    self.log.append(chunk); self.output = self.log.text
                }
                state = result.succeeded ? .succeeded : .failed
                message = result.succeeded ? "Zapp finished successfully."
                    : result.signalled ? "Zapp stopped unexpectedly (signal \(result.status)). Check the output before retrying."
                    : "Zapp could not finish (exit \(result.status)). Check the output before retrying."
            } catch {
                state = .failed; message = "Could not flash firmware: \(error.localizedDescription)"
            }
        }
    }
}
