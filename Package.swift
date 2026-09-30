// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Keyfinder",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "KeyfinderCore", targets: ["KeyfinderCore"]),
        .executable(name: "Keyfinder", targets: ["Keyfinder"]),
        .executable(name: "KeyfinderCoreChecks", targets: ["KeyfinderCoreTests"])
    ],
    targets: [
        .target(name: "KeyfinderCore", resources: [.process("Resources")]),
        .executableTarget(name: "Keyfinder", dependencies: ["KeyfinderCore"]),
        // A standalone runner works with Apple's Command Line Tools; XCTest
        // and Swift Testing are only shipped with full Xcode on some Macs.
        .executableTarget(name: "KeyfinderCoreTests", dependencies: ["KeyfinderCore"], path: "Tests/KeyfinderCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
