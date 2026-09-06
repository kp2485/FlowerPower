// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FlowerPowerCore",
    // Platform versions are given as strings rather than enum cases so the
    // manifest does not need a toolchain that has heard of the newest release
    // just to parse. The engine is also built and tested on Windows, where
    // none of these apply.
    platforms: [
        .iOS("27.0"),
        .watchOS("27.0"),
        .macOS("27.0")
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
        .target(name: "FlowerPowerCore", swiftSettings: .strict),
        .target(
            name: "FlowerPowerGame",
            dependencies: ["FlowerPowerCore"],
            swiftSettings: .strict
        ),
        .executableTarget(
            name: "BeeSim",
            dependencies: ["FlowerPowerCore"],
            swiftSettings: .strict
        ),
        .testTarget(name: "FlowerPowerCoreTests", dependencies: ["FlowerPowerCore"]),
        .testTarget(
            name: "FlowerPowerGameTests",
            dependencies: ["FlowerPowerGame", "FlowerPowerCore"]
        )
    ]
)

extension [SwiftSetting] {

    /// Swift 6 language mode across the package.
    ///
    /// The engine is almost entirely value types that are already `Sendable`,
    /// which is what makes this affordable: the determinism the whole design
    /// rests on and the data-race safety the compiler wants turn out to be the
    /// same property. Test targets are left in Swift 5 mode, because
    /// XCTest fixtures are shared mutable state by nature and rewriting two
    /// hundred passing tests to satisfy the checker would be churn.
    static var strict: [SwiftSetting] {
        [.swiftLanguageMode(.v6)]
    }
}
