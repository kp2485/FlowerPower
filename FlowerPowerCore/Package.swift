// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FlowerPowerCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(name: "FlowerPowerCore", targets: ["FlowerPowerCore"]),
        // Balance tooling: runs the engine headless and prints a trajectory, so
        // tuning is driven by observed colony behaviour rather than guesswork.
        .executable(name: "beesim", targets: ["BeeSim"])
    ],
    targets: [
        .target(name: "FlowerPowerCore"),
        .executableTarget(name: "BeeSim", dependencies: ["FlowerPowerCore"]),
        .testTarget(name: "FlowerPowerCoreTests", dependencies: ["FlowerPowerCore"])
    ]
)
