// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppDropCore",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AppDropCore", targets: ["AppDropCore"]),
        .executable(name: "appdropctl", targets: ["AppDropCtl"])
    ],
    targets: [
        .target(
            name: "AppDropCore",
            path: "Sources/AppDropCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "AppDropCtl",
            dependencies: ["AppDropCore"],
            path: "Sources/AppDropCtl"
        ),
        .testTarget(
            name: "AppDropCoreTests",
            dependencies: ["AppDropCore"],
            path: "Tests/AppDropCoreTests"
        )
    ]
)
