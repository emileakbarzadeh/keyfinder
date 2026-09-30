import Foundation

enum CoreResources {
    /// Resolve relative to the executable so installed apps have no dependency
    /// on SwiftPM's absolute build path (which also varies between Nix builds).
    static let bundle: Bundle = {
        #if os(macOS)
        let locations = [Bundle.main.resourceURL, Bundle.main.bundleURL,
                         Bundle.main.executableURL?.deletingLastPathComponent()]
        for directory in locations.compactMap({ $0 }) {
            if let packaged = Bundle(url: directory.appendingPathComponent("Keyfinder_KeyfinderCore.bundle")) { return packaged }
        }
        fatalError("Keyfinder's resource bundle is missing beside the executable or inside the app's Resources directory.")
        #else
        return Bundle.module
        #endif
    }()
}
