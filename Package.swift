// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "nook",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NookKit", targets: ["NookKit"]),
        .executable(name: "Nook", targets: ["Nook"]),
        .executable(name: "nookctl", targets: ["NookCommandLine"]),
    ],
    targets: [
        .target(name: "NookKit", path: "Sources/kit"),
        .target(name: "NookCore", path: "Sources/core"),
        .target(name: "NookSystem", dependencies: ["NookCore"], path: "Sources/system"),
        .executableTarget(name: "Nook", dependencies: ["NookCore", "NookSystem"], path: "Sources/manager"),
        .executableTarget(name: "NookCommandLine", dependencies: ["NookCore", "NookSystem"], path: "Sources/cli"),
        .testTarget(name: "NookCoreTests", dependencies: ["NookCore"], path: "Tests/core-tests"),
        .testTarget(name: "NookSystemTests", dependencies: ["NookSystem", "NookCore"], path: "Tests/system-tests"),
        .testTarget(name: "NookCommandLineTests", dependencies: ["NookCommandLine", "NookCore"], path: "Tests/command-line-tests"),
    ]
)
