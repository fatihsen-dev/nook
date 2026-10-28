// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clock",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(
            name: "Clock",
            dependencies: [.product(name: "NookKit", package: "nook")],
            path: "Sources"),
    ]
)
