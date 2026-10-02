// A subprocess fixture, never installed in Keyfinder.app. No USB libraries.
import Foundation
import Darwin

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--keyfinder-fixture"] { print("KeyfinderZappFixture v1 (no USB)"); exit(0) }
guard arguments.count == 2, arguments[0] == "flash",
      let data = FileManager.default.contents(atPath: arguments[1]),
      let text = String(data: data, encoding: .utf8), text.hasPrefix("Keyfinder test fixture\n") else { exit(64) }
FileHandle.standardOutput.write(Data("path=\(arguments[1])\n".utf8))
FileHandle.standardError.write(Data("stderr is captured\n".utf8))
if text.contains("await-output") {
    // The parent must see a short prompt before this process exits. A bounded
    // diagnostic-only wait catches pipe readers that buffer until EOF.
    let acknowledgement = URL(fileURLWithPath: arguments[1]).appendingPathExtension("ack")
    for _ in 0..<200 {
        if FileManager.default.fileExists(atPath: acknowledgement.path) { exit(0) }
        usleep(5_000)
    }
    exit(24)
}
if text.contains("large-output") {
    for _ in 0..<100 { FileHandle.standardOutput.write(Data(repeating: 65, count: 4096)) }
    FileHandle.standardOutput.write(Data("\nfinal output\n".utf8))
}
if text.contains("signal") { raise(SIGTERM) }
exit(text.contains("failure") ? 23 : 0)
