import Foundation

enum CoreResources {
    /// SwiftPM's build-tree fallback is not available in an installed .app.
    static let bundle: Bundle = {
        if let directory = Bundle.main.resourceURL,
           let packaged = Bundle(url: directory.appendingPathComponent("Keyfinder_KeyfinderCore.bundle")) { return packaged }
        return Bundle.module
    }()
}
