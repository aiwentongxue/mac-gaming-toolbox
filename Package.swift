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
        .executable(name: "MacGameToolboxPrivilegedHelper", targets: ["MacGameToolboxPrivilegedHelper"])
    ],
    targets: [
        .target(name: "MacGameToolboxCore"),
        .target(
            name: "MacGameToolboxClickFlow",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "MacGameToolbox",
            dependencies: ["MacGameToolboxCore", "MacGameToolboxClickFlow"],
            resources: [.process("Assets.xcassets")],
            linkerSettings: [.linkedFramework("ServiceManagement"), .linkedFramework("Security")]
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
