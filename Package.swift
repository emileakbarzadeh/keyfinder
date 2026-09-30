// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Keyfinder",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "KeyfinderCore", targets: ["KeyfinderCore"]),
        .executable(name: "Keyfinder", targets: ["Keyfinder"])
    ],
    targets: [
        .target(name: "KeyfinderCore", resources: [.process("Resources")]),
        .executableTarget(name: "Keyfinder", dependencies: ["KeyfinderCore"]),
        .testTarget(name: "KeyfinderCoreTests", dependencies: ["KeyfinderCore"])
    ],
    swiftLanguageModes: [.v5]
)
