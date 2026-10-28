// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NowPlaying",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(
            name: "NowPlaying",
            dependencies: [.product(name: "NookKit", package: "nook")],
            path: "Sources",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Info.plist"]),
            ]),
    ]
)
