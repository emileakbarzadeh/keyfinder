import AppKit
import KeyfinderCore

@main enum KeyfinderMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            if arguments.first == "--render-previews", arguments.count == 2 {
                try Diagnostics.renderPreviews(to: URL(fileURLWithPath: arguments[1], isDirectory: true))
                return
            }
            if arguments.first == "--render-icon", arguments.count == 2 {
                try Diagnostics.renderIcon(to: URL(fileURLWithPath: arguments[1]))
                return
            }
            if arguments.first == "--smoke-test", arguments.count == 2 {
                Diagnostics.runSmokeTest(reportURL: URL(fileURLWithPath: arguments[1]))
                app.run()
                if !Diagnostics.smokePassed { exit(1) }
                return
            }
            if arguments.first == "--diagnostics" {
                let snapshot = try LayoutSnapshot.bundled()
                print("Keyfinder 1.0 · macOS 26+\nBundled layout: \(snapshot.layoutID)/\(snapshot.revisionID)\nLayers: \(snapshot.layers.count) · keys: \(try MoonlanderGeometry.load().count)\nPeriodic jobs: none\nUSB: ZSA raw HID, non-exclusive, callbacks only")
                return
            }
            if !arguments.isEmpty && arguments != ["--background"] {
                fputs("Usage: Keyfinder [--background | --diagnostics | --render-previews directory | --render-icon path | --smoke-test report.json]\n", stderr)
                exit(2)
            }
        } catch {
            fputs("Keyfinder: \(error.localizedDescription)\n", stderr); exit(1)
        }
        let delegate = AppDelegate(backgroundLaunch: arguments == ["--background"])
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
