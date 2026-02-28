// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TabXHost",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "tabx-host", targets: ["TabXHostRunner"]),
        .library(name: "TabXHostLib", targets: ["TabXHostLib"]),
    ],
    targets: [
        // All implementation logic lives here so tests can import it.
        .target(
            name: "TabXHostLib",
            path: "Sources/TabXHost",
            linkerSettings: [
                .linkedFramework("NaturalLanguage"),
            ]
        ),
        // Thin entry-point that delegates to TabXHostLib.
        .executableTarget(
            name: "TabXHostRunner",
            dependencies: ["TabXHostLib"],
            path: "Sources/TabXHostRunner"
        ),
        .testTarget(
            name: "TabXHostTests",
            dependencies: ["TabXHostLib"],
            path: "Tests/TabXHostTests"
        ),
    ]
)
