import Testing
import Foundation
@testable import FlowerPowerCore

/// The handful of stands that bloom in winter, and what they are worth.
///
/// Until 2026-09-24 winter's forage multiplier was zero, so a rosemary bush in
/// January was exactly as much use as a clover stand gone to seed. These pin
/// the two halves of the change: a winter bloomer on a day the bees can fly
/// gives something and grows back overnight, and nothing else about winter
/// moves — a stand out of bloom gives nothing, a cold day gives nothing, and
/// a multiplier of zero is the engine as it was.
@Suite("Winter forage")
struct WinterForageTests {

    /// Late winter, mid-morning. Past `Season.winterDormancyEnds`, so the
    /// cluster has loosened and there are bees working rather than idling.
    private let winterDay = Season.daysPerSeason * 3 + 60

    /// One stand at 200 m, a working force, room in the comb, and the day's
    /// weather fixed. Runs one daylight hour of foraging and then one night of
    /// regrowth on a stand stripped bare, and says what each gave.
    private func forage(
        _ species: FlowerSpecies,
        winterForage: Double,
        temperature: Double = 14
    ) -> (taken: Double, regrown: Double) {
        var config = SimulationConfig.standard
        config.winterForageOverride = winterForage

        var simulation = Fixture.barrenSimulation()
        simulation.config = config
        // The clock moves before the photograph is registered, because a
        // stand fades from the day it was photographed.
        simulation.clock = SimClock(
            epoch: epoch, tick: winterDay * SimClock.ticksPerDay + 11
        )
        simulation.registerPhotograph(
            photoLocalIdentifier: "winter", species: species,
            confidence: 1, takenAt: epoch
        )
        simulation.setDistance(200, forPatchAt: 0)
        simulation.mutateWorld { world in
            world.hive.comb = Comb(workerCells: 300, droneCells: 40, capacity: 700)
            world.hive.resources.add(60, of: .honey)
            for index in 0..<40 {
                world.hive.bees.append(Bee(
                    id: EntityID(rawValue: UInt64(330_000 + index)),
                    kind: .worker, stage: .adult, daysInStage: 25
                ))
            }
        }
        simulation.forceWeather(sky: .clear, temperature: temperature)

        var world = simulation.world
        var context = TickContext(
            clock: simulation.clock, config: config,
            rng: SeededRandom(seed: 1), ids: IDGenerator()
        )
        #expect(context.season == .winter)
        #expect(context.isDaylight)

        let before = world.patches[0].remainingNectar + world.patches[0].remainingPollen
        ForagingSystem().update(&world, &context)
        let after = world.patches[0].remainingNectar + world.patches[0].remainingPollen

        _ = world.patches[0].harvest(
            nectar: world.patches[0].remainingNectar,
            pollen: world.patches[0].remainingPollen
        )
        PatchSystem().updateDaily(&world, &context)
        let regrown = world.patches[0].remainingNectar + world.patches[0].remainingPollen

        return (before - after, regrown)
    }

    @Test("A stand in bloom in winter gives something on a flying day", arguments: [
        FlowerCatalogue.rosemary, FlowerCatalogue.winterHeather, FlowerCatalogue.mahonia
    ])
    func winterBloomerYields(species: FlowerSpecies) {
        #expect(species.isInBloom(during: .winter))
        let result = forage(species, winterForage: 0.3)
        #expect(result.taken > 0, "\(species.commonName) gave nothing on a mild winter day")
        #expect(result.regrown > 0, "\(species.commonName) did not grow back overnight")
    }

    @Test("A stand out of bloom in winter gives nothing and grows nothing")
    func outOfBloomGivesNothing() {
        let clover = FlowerCatalogue.whiteClover
        #expect(!clover.isInBloom(during: .winter))
        let result = forage(clover, winterForage: 0.3)
        #expect(result.taken == 0)
        #expect(result.regrown == 0)
    }

    @Test("A winter bloomer on a day too cold to fly gives nothing")
    func coldDayGivesNothing() {
        #expect(forage(FlowerCatalogue.mahonia, winterForage: 0.3, temperature: 5).taken == 0)
    }

    @Test("A multiplier of zero is winter as it was")
    func zeroIsTheOldWinter() {
        let result = forage(FlowerCatalogue.mahonia, winterForage: 0)
        #expect(result.taken == 0)
        #expect(result.regrown == 0)
    }

    @Test("Only winter is changed")
    func otherSeasonsUntouched() {
        var config = SimulationConfig.standard
        config.winterForageOverride = 0.3
        for season in Season.allCases where season != .winter {
            #expect(config.forageMultiplier(in: season) == season.forageMultiplier)
            #expect(config.patchRegrowthMultiplier(in: season) == season.patchRegrowthMultiplier)
        }
        #expect(config.forageMultiplier(in: .winter) == 0.3)
        #expect(config.patchRegrowthMultiplier(in: .winter) == 0.3)
    }

    /// Every save on every phone carries a `config`, and a synthesised
    /// `Decodable` throws on a missing non-optional key. The override is an
    /// optional for exactly this reason, and this is the test that notices if
    /// somebody tidies it into a plain `Double`.
    @Test("A config saved before winter forage existed still decodes")
    func olderConfigDecodes() throws {
        let encoded = try JSONEncoder().encode(SimulationConfig.standard)
        var fields = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        fields.removeValue(forKey: "winterForageOverride")
        let older = try JSONSerialization.data(withJSONObject: fields)

        let decoded = try JSONDecoder().decode(SimulationConfig.self, from: older)
        #expect(decoded.winterForageOverride == nil)
        #expect(decoded.winterForageMultiplier == SimulationConfig.shippedWinterForage)
        #expect(decoded == SimulationConfig.standard)
    }
}
