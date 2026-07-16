// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacGameToolbox",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacGameToolboxCore", targets: ["MacGameToolboxCore"]),
        .executable(name: "MacGameToolbox", targets: ["MacGameToolbox"]),
        .executable(name: "MacGameToolboxPrivilegedHelper", targets: ["MacGameToolboxPrivilegedHelper"])
    ],
    targets: [
        .target(name: "MacGameToolboxCore"),
        .executableTarget(
            name: "MacGameToolbox",
            dependencies: ["MacGameToolboxCore"],
            resources: [.process("Assets.xcassets")],
            linkerSettings: [.linkedFramework("ServiceManagement"), .linkedFramework("Security"), .linkedFramework("Carbon")]
        ),
        .executableTarget(
            name: "MacGameToolboxPrivilegedHelper",
            dependencies: ["MacGameToolboxCore"],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .testTarget(name: "MacGameToolboxCoreTests", dependencies: ["MacGameToolboxCore"])
    ]
)
