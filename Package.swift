// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacGameToolbox",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacGameToolboxCore", targets: ["MacGameToolboxCore"]),
        .library(name: "MacGameToolboxClickFlow", targets: ["MacGameToolboxClickFlow"]),
        .executable(name: "MacGameToolbox", targets: ["MacGameToolbox"]),
        .executable(name: "MacGameToolboxPrivilegedHelper", targets: ["MacGameToolboxPrivilegedHelper"]),
        .executable(name: "MacGameToolboxAppDropHelper", targets: ["MacGameToolboxAppDropHelper"])
    ],
    dependencies: [
        .package(path: "Packages/AppDropCore")
    ],
    targets: [
        .target(name: "MacGameToolboxCore"),
        .target(
            name: "MacGameToolboxClickFlow",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "MacGameToolbox",
            dependencies: [
                "MacGameToolboxCore",
                "MacGameToolboxClickFlow",
                .product(name: "AppDropCore", package: "AppDropCore")
            ],
            resources: [
                .process("Assets.xcassets"),
                .copy("AppIcon.icon"),
                .process("AppDropFeature/Resources")
            ],
            linkerSettings: [.linkedFramework("ServiceManagement"), .linkedFramework("Security")]
        ),
        .executableTarget(
            name: "MacGameToolboxAppDropHelper",
            dependencies: [.product(name: "AppDropCore", package: "AppDropCore")],
            path: "Sources/AppDropHelper",
            linkerSettings: [.linkedFramework("ServiceManagement"), .linkedFramework("UserNotifications")]
        ),
        .executableTarget(
            name: "MacGameToolboxPrivilegedHelper",
            dependencies: ["MacGameToolboxCore"],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .testTarget(name: "MacGameToolboxCoreTests", dependencies: ["MacGameToolboxCore"]),
        .testTarget(name: "MacGameToolboxClickFlowTests", dependencies: ["MacGameToolboxClickFlow"])
    ]
)
