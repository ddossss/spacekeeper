// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Spacekeeper",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Spacekeeper", targets: ["Spacekeeper"])],
    targets: [
        .target(name: "SpacekeeperCore", resources: [.process("Resources")]),
        .executableTarget(name: "Spacekeeper", dependencies: ["SpacekeeperCore"]),
        .testTarget(name: "SpacekeeperCoreTests", dependencies: ["SpacekeeperCore"])
    ]
)
