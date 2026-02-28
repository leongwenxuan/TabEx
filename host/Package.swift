// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TabXHost",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "tabx-host", targets: ["TabXHostRunner"]),
        .executable(name: "TabXApp", targets: ["TabXApp"]),
        .library(name: "TabXHostLib", targets: ["TabXHostLib"]),
    ],
    targets: [
        // All implementation logic lives here so tests can import it.
        .target(
            name: "TabXHostLib",
            path: "Sources/TabXHost"
        ),
        // Thin entry-point that delegates to TabXHostLib.
        .executableTarget(
            name: "TabXHostRunner",
            dependencies: ["TabXHostLib"],
            path: "Sources/TabXHostRunner"
        ),
        // macOS menu bar application.
        .executableTarget(
            name: "TabXApp",
            dependencies: ["TabXHostLib"],
            path: "Sources/TabXApp"
        ),
        .testTarget(
            name: "TabXHostTests",
            dependencies: ["TabXHostLib"],
            path: "Tests/TabXHostTests"
        ),
    ]
)
