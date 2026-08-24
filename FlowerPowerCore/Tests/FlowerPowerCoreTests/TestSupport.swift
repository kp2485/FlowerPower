import Foundation
@testable import FlowerPowerCore

/// Fixed epoch so every test starts from the same instant.
let epoch = Date(timeIntervalSince1970: 1_700_000_000)

extension Date {
    /// Real time equivalent of `days` simulated days at the default tick rate.
    static func afterSimulated(days: Double, from start: Date = epoch) -> Date {
        start.addingTimeInterval(days * Double(SimClock.ticksPerDay) * 300)
    }

    static func afterSimulated(hours: Double, from start: Date = epoch) -> Date {
        start.addingTimeInterval(hours * 300)
    }
}

enum Fixture {

    static let clover = FlowerSpecies(
        id: "clover",
        commonName: "White Clover",
        rarity: .common,
        nectarRichness: 1.2,
        pollenRichness: 1.0,
        bloomSeasons: [.spring, .summer, .autumn]
    )

    static let heather = FlowerSpecies(
        id: "heather",
        commonName: "Heather",
        rarity: .uncommon,
        nectarRichness: 1.6,
        pollenRichness: 0.8,
        bloomSeasons: [.autumn],
        isKeystone: true
    )

    static let crocus = FlowerSpecies(
        id: "crocus",
        commonName: "Crocus",
        rarity: .common,
        nectarRichness: 0.7,
        pollenRichness: 1.4,
        bloomSeasons: [.spring]
    )

    /// A colony with plentiful forage close to hand, so tests that are not
    /// about scarcity are not accidentally about scarcity.
    static func thrivingSimulation(
        patches: Int = 14,
        distance: Double = 300,
        config: SimulationConfig = .standard,
        seed: UInt64 = 42,
        locationType: HiveLocationType = .livingTreeCavity,
        drawnComb: Int = 260
    ) -> Simulation {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: locationType),
            startingAt: epoch,
            config: config,
            seed: seed
        )

        // Give it comb an established colony would have drawn. A founding
        // colony has only 66 cells, and a test that then adds a few hundred
        // units of honey fills every one — leaving the queen nowhere to lay and
        // the foragers nowhere to put nectar. That is real behaviour (a
        // honey-bound colony), but it is not what most of these tests are for.
        simulation.mutateWorld { world in
            world.hive.comb = Comb(
                workerCells: drawnComb,
                droneCells: drawnComb / 7,
                capacity: locationType.maximumCells
            )
        }

        for index in 0..<patches {
            simulation.registerPhotograph(
                photoLocalIdentifier: "photo-\(index)",
                species: clover,
                confidence: 0.9,
                coordinate: nil,
                takenAt: epoch
            )
            simulation.setDistance(distance, forPatchAt: index)
        }

        return simulation
    }

    /// A colony with no forage at all.
    static func barrenSimulation(seed: UInt64 = 7) -> Simulation {
        Simulation.newGame(at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: seed)
    }
}

extension Simulation {

    /// Test hook: patches registered without coordinates default to the nominal
    /// distance, and several tests need to control it precisely.
    mutating func setDistance(_ metres: Double, forPatchAt index: Int) {
        guard world.patches.indices.contains(index) else { return }
        world.patches[index].distanceMetres = metres
    }

    var totalRemainingNectar: Double {
        patches.reduce(0) { $0 + $1.remainingNectar }
    }

    var totalRemainingPollen: Double {
        patches.reduce(0) { $0 + $1.remainingPollen }
    }

    /// Runs `days` simulated days by stepping, so tests do not have to reason
    /// about the real-time mapping.
    @discardableResult
    mutating func runDays(_ days: Int) -> CatchUpReport {
        var report = CatchUpReport()
        for _ in 0..<(days * SimClock.ticksPerDay) {
            for event in step() { report.record(event) }
            report.ticksSimulated += 1
        }
        return report
    }

    /// Steps until the simulated clock reaches the given hour of day.
    mutating func runUntilHour(_ hour: Int) {
        var guardrail = 0
        while clock.hourOfDay != hour && guardrail < 1000 {
            _ = step()
            guardrail += 1
        }
    }

    /// Forces settled, benign conditions so a test can isolate one mechanism
    /// from the weather.
    mutating func forceWeather(
        sky: Sky = .clear,
        temperature: Double = 22,
        humidity: Double = 0.5,
        wind: Double = 1
    ) {
        world.weather = Weather(
            sky: sky,
            temperatureCelsius: temperature,
            humidity: humidity,
            windSpeed: wind
        )
    }

    /// Direct world access for arranging test preconditions.
    mutating func mutateWorld(_ body: (inout World) -> Void) {
        body(&world)
    }

    /// Pretends the colony has been taking in nectar hard for a week, so
    /// flow-gated behaviour — comb building especially — can be tested without
    /// having to simulate a whole spring first.
    mutating func simulateNectarFlow() {
        let perDay = Double(world.hive.adultCount) * World.flowThresholdPerBee * 3
        world.recentNectarIntake = Array(repeating: perDay, count: World.intakeWindow)
        world.todayNectarIntake = perDay
    }
}
