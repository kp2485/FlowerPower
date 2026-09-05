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
        // The simulation. No UI, no Apple-only frameworks, no I/O.
        .library(name: "FlowerPowerCore", targets: ["FlowerPowerCore"]),
        // Everything between the simulation and SwiftUI: the observable store
        // the views bind to, and the save file. Deliberately outside the Xcode
        // targets so it can be compiled and tested without a Mac — this is the
        // layer where the app's own bugs live.
        .library(name: "FlowerPowerGame", targets: ["FlowerPowerGame"]),
        // Balance tooling: runs the engine headless and prints a trajectory, so
        // tuning is driven by observed colony behaviour rather than guesswork.
        .executable(name: "beesim", targets: ["BeeSim"])
    ],
    targets: [
        .target(name: "FlowerPowerCore"),
        .target(name: "FlowerPowerGame", dependencies: ["FlowerPowerCore"]),
        .executableTarget(name: "BeeSim", dependencies: ["FlowerPowerCore"]),
        .testTarget(name: "FlowerPowerCoreTests", dependencies: ["FlowerPowerCore"]),
        .testTarget(
            name: "FlowerPowerGameTests",
            dependencies: ["FlowerPowerGame", "FlowerPowerCore"]
        )
    ]
)
