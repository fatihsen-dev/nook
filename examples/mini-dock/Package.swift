// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiniDock",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(
            name: "MiniDock",
            dependencies: [.product(name: "NookKit", package: "nook")],
            path: "Sources"),
    ]
)
