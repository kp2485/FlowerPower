import Foundation
import Testing
@testable import FlowerPowerCore

/// Phase 2 of `docs/WORLD.md`: the country.
///
/// Wild flowers, the fog, discovery by foragers, scouts as a decision, and the
/// biome tables on threats and disease. Three things run through all of it and
/// are what these tests are really about.
///
/// **A chunk's flowers are a pure function of the seed**, so the literals below
/// are the map every player has: a change to the hash that looks harmless moves
/// everybody's hedges and must fail here rather than in somebody's save.
///
/// **They exist only where a bee has been.** Generation is not registration —
/// the generator will happily describe a parish at the far edge of the range,
/// and until the colony reaches it there is no patch, no id and nothing in the
/// save.
///
/// **And nothing is ever found past the range.** Eight kilometres is the
/// engine's own edge, and it is the edge of the world.
@Suite("The country")
struct CountryTests {

    // MARK: - What grows where, exactly

    /// Pinned to seed 2026, the seed `WorldGeneratorTests` pins the chunks
    /// themselves against, so the two sets of literals describe one map.
    ///
    /// The village east-north-east of the home chunk, where the crocus and the
    /// apples are. Six stands, because a village is gardens all the way
    /// through; the willow country around it gets five.
    @Test("Wild flowers are pinned to the seed")
    func wildFlowersAreStable() {
        let generator = WorldGenerator(seed: 2026)
        let village = ChunkCoordinate(q: 1, r: -1)
        #expect(generator.biome(at: village) == .village)

        let seeds = generator.wildPatches(in: village)
        #expect(seeds.count == 6)

        #expect(seeds.map(\.cell) == [
            HexCoordinate(q: 2, r: -5),
            HexCoordinate(q: 2, r: -6),
            HexCoordinate(q: 3, r: -8),
            HexCoordinate(q: 4, r: -9),
            HexCoordinate(q: 6, r: -6),
            HexCoordinate(q: 4, r: -10)
        ])
        #expect(seeds.map(\.speciesID) == [
            "aster", "apple", "crocus", "aster", "rosemary", "apple"
        ])
        // Each stand's own size, which is what stops two hedges being the same
        // hedge. Compared loosely because the value is a unit draw scaled, and
        // the literal is here to catch a changed hash rather than a changed
        // rounding mode.
        #expect(abs(seeds[0].variation - 0.711_305) < 0.000_01)
        #expect(abs(seeds[5].variation - 1.271_973) < 0.000_01)
    }

    @Test("The home chunk of seed 2026 is the willow country it always was")
    func homeChunkIsStable() {
        let generator = WorldGenerator(seed: 2026)
        let seeds = generator.wildPatches(in: .origin)
        #expect(seeds.count == 5)
        #expect(seeds.map(\.speciesID) == [
            "meadowsweet", "meadowsweet", "balsam", "balsam", "willow"
        ])
    }

    /// Density thins the country without rearranging it: the stands a thinner
    /// world keeps are the same stands, in the same cells, with the same
    /// flowers on them. Otherwise sweeping the lever would be sweeping two
    /// things at once.
    @Test("Density takes a prefix of the same ranking")
    func densityThinsRatherThanReshuffles() {
        let generator = WorldGenerator(seed: 2026)
        let chunk = ChunkCoordinate(q: 1, r: -1)

        let full = generator.wildPatches(in: chunk, density: 1)
        let thin = generator.wildPatches(in: chunk, density: 0.4)

        #expect(thin.count == 2)
        #expect(thin.allSatisfy { seed in full.contains(seed) })
    }

    @Test("Asking twice, and in a different order, gives the same flowers")
    func wildFlowersDoNotDependOnOrder() {
        let generator = WorldGenerator(seed: 7)
        let coordinates = (-3...3).flatMap { q in (-3...3).map { ChunkCoordinate(q: q, r: $0) } }

        let forwards = coordinates.map { generator.wildPatches(in: $0) }
        let backwards = coordinates.reversed().map { generator.wildPatches(in: $0) }
        #expect(forwards == backwards.reversed())
    }

    @Test("Every wild species resolves in the catalogue")
    func wildSpeciesResolve() {
        let generator = WorldGenerator(seed: 55)
        for q in -4...4 {
            for r in -4...4 {
                for seed in generator.wildPatches(in: ChunkCoordinate(q: q, r: r)) {
                    #expect(
                        FlowerCatalogue.species(withID: seed.speciesID) != nil,
                        "\(seed.speciesID) is not in the catalogue"
                    )
                }
            }
        }
    }

    /// Common plants are commoner. Not a precise distribution — the point of
    /// the weighting is that a hedge is mostly bramble — but a rare plant
    /// turning up as often as a common one would mean the weights are not
    /// reaching the draw at all.
    @Test("Rarity weights the draw")
    func rarityWeightsTheDraw() {
        let expanded = WorldGenerator.weightedSpecies(for: .hedgerow)
        let bramble = expanded.filter { $0 == "bramble" }.count
        let borage = expanded.filter { $0 == "borage" }.count
        #expect(bramble > 0)
        #expect(borage > 0)
        #expect(bramble != borage || FlowerCatalogue.bramble.rarity == FlowerCatalogue.borage.rarity)
    }

    // MARK: - Generated is not registered

    @Test("A founding colony holds the flowers of its six neighbours and no others")
    func foundingRegistersTheKnownCountry() {
        let simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 2026
        )
        guard let terrain = simulation.terrain else { Issue.record("no terrain"); return }

        let wild = simulation.wildPatches
        #expect(!wild.isEmpty)

        // Every wild patch stands in a chunk the colony has discovered, and
        // none of them in the cell the bees live in.
        for patch in wild {
            guard let cell = patch.cell else { Issue.record("a wild patch nowhere"); continue }
            #expect(terrain.hasDiscovered(ChunkCoordinate.containing(cell)))
            #expect(cell != .origin, "nothing grows in the nest")
        }

        // And the count is what the generator describes for the seven, less
        // the nest's own cell where one happens to fall, and less anything the
        // garden is already standing on.
        let density = SimulationConfig.standard.wildPatchDensity
        let described = terrain.discovered
            .flatMap { terrain.generator.wildPatches(in: $0, density: density) }
            .filter { $0.cell != .origin }
            .filter { $0.cell.metresFromOrigin <= FlowerPatch.maximumForagingRange }
        #expect(wild.count == described.count)
        #expect(wild.contains { ChunkCoordinate.containing($0.cell ?? .origin) == terrain.home },
                "the country grows right up to the nest")
    }

    @Test("Undiscovered country has no patches in the save")
    func undiscoveredCountryIsNotRegistered() {
        let simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 2026
        )
        let before = simulation.wildPatches.count

        // A parish two chunks out: generated, describable, and not the
        // colony's business until somebody flies there.
        let far = ChunkCoordinate(q: 2, r: 0)
        #expect(simulation.terrain?.hasDiscovered(far) == false)
        #expect(simulation.terrain?.generator.wildPatches(in: far).isEmpty == false)
        #expect(simulation.wildPatches.count == before)
    }

    @Test("Wild patches never fade and carry the sentinel")
    func wildPatchesNeverFade() {
        let simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 2026
        )
        for patch in simulation.wildPatches {
            #expect(patch.registeredOnDay == nil)
            #expect(patch.vigour(onDay: 10_000, config: .standard) == 1)
            #expect(patch.photoLocalIdentifier.hasPrefix(FlowerPatch.wildPhotoPrefix))
            #expect(patch.origin == .wild)
        }
    }

    /// The balance tooling prunes stripped patches on every restock, for
    /// hundreds of simulated years. A wild stand pruned out of season would
    /// quietly empty the countryside over a long run.
    @Test("Pruning never takes the countryside away")
    func pruningKeepsWildPatches() {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 2026
        )
        let before = simulation.wildPatches.count
        for index in simulation.world.patches.indices {
            simulation.world.patches[index].remainingNectar = 0
            simulation.world.patches[index].remainingPollen = 0
        }
        simulation.pruneDepletedPatches()
        #expect(simulation.wildPatches.count == before)
    }

    // MARK: - The fog

    @Test("Rumoured ground is what touches the known and nothing else")
    func rumourIsDerivedFromTheKnown() {
        let terrain = Terrain(seed: 2026)
        let rumoured = terrain.rumoured

        #expect(!rumoured.isEmpty)
        for chunk in rumoured {
            #expect(!terrain.hasDiscovered(chunk))
            #expect(chunk.neighbours.contains { terrain.hasDiscovered($0) })
        }
        // No duplicates: a chunk touching two known ones is one rumour.
        #expect(Set(rumoured).count == rumoured.count)
    }

    @Test("Rumour is in a fixed order")
    func rumourOrderIsFixed() {
        let terrain = Terrain(seed: 2026)
        #expect(terrain.rumoured == terrain.rumoured)
        #expect(Terrain(seed: 2026).rumoured == terrain.rumoured)
    }

    /// Everything on the map was reached by a bee, and a bee's world is a
    /// circle eight kilometres across. Nothing past that is ever rumoured, so
    /// nothing past it can ever be discovered.
    @Test("Nothing beyond flying range is ever rumoured")
    func rumourStopsAtTheRange() {
        var terrain = Terrain(seed: 2026)

        // Walk east as far as the range allows, discovering as we go, and
        // check the frontier never steps over the edge.
        for step in 1...12 {
            let chunk = ChunkCoordinate(q: step, r: 0)
            guard Terrain.isWithinFlight(chunk) else { break }
            terrain.discover(chunk)
        }

        for chunk in terrain.rumoured {
            #expect(chunk.centre.metresFromOrigin <= FlowerPatch.maximumForagingRange)
        }
        #expect(terrain.rumoured.contains { $0.q > 3 })
    }

    @Test("Discovering a chunk plants it, once")
    func discoveryPlantsOnce() {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 2026
        )
        let before = simulation.wildPatches.count
        let target = simulation.rumouredChunks.first!

        var ids = IDGenerator(startingAt: 900_000)
        let planted = simulation.world.discover(
            target, ids: &ids, config: .standard, on: 0, at: epoch
        )
        #expect(planted > 0)
        #expect(simulation.wildPatches.count == before + planted)
        #expect(simulation.terrain?.hasDiscovered(target) == true)

        // A second discovery of the same ground is not a second hedge.
        let again = simulation.world.discover(
            target, ids: &ids, config: .standard, on: 0, at: epoch
        )
        #expect(again == 0)
        #expect(simulation.wildPatches.count == before + planted)
    }

    @Test("A patch beyond the range is described but never planted")
    func patchesBeyondRangeAreNotPlanted() {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 2026
        )
        var ids = IDGenerator(startingAt: 900_000)

        // Far outside the range. The generator will describe it happily.
        let far = ChunkCoordinate(q: 30, r: 0)
        #expect(simulation.terrain?.generator.wildPatches(in: far).isEmpty == false)

        simulation.world.terrain?.discover(far)
        let planted = simulation.world.plantWildFlowers(
            of: far, ids: &ids, config: .standard, on: 0, at: epoch
        )
        #expect(planted == 0)
        for patch in simulation.allPatches {
            #expect(patch.distanceMetres <= FlowerPatch.maximumForagingRange)
        }
    }

    // MARK: - Scouts

    @Test("The scout decision is shut until a flow is on")
    func scoutDecisionNeedsAFlow() {
        let simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 2026
        )
        // A founding colony has brought in nothing at all.
        #expect(simulation.world.isInFlow(.standard) == false)
        #expect(simulation.scoutDecisionOpen == false)
        #expect(simulation.scoutsOut == false)
        #expect(simulation.scoutsDaysRemaining == nil)
    }

    @Test("Sending scouts is refused when the decision is shut")
    func scoutsRefusedWhenShut() {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 2026
        )
        let went = simulation.sendScouts()
        #expect(went == false)
        #expect(simulation.scoutsOut == false)
    }

    @Test("A flow with rumoured ground opens it, and the party goes")
    func scoutsGoInAFlow() {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 2026
        )
        simulation.world.recentNectarIntake = Array(
            repeating: Double(simulation.hive.adultCount) * 10, count: 7
        )

        #expect(simulation.scoutDecisionOpen)
        let went = simulation.sendScouts()
        #expect(went)
        #expect(simulation.scoutsOut)
        #expect(simulation.scoutsDaysRemaining == simulation.config.scoutDays)

        // And not twice.
        let twice = simulation.sendScouts()
        #expect(twice == false)
        #expect(simulation.scoutDecisionOpen == false)
    }

    @Test("Scouts come back with every rumoured stretch of country")
    func scoutsRevealTheRing() {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 2026
        )
        simulation.world.recentNectarIntake = Array(
            repeating: Double(simulation.hive.adultCount) * 10, count: 7
        )
        let expected = simulation.rumouredChunks
        #expect(expected.count > 0)
        let known = simulation.terrain?.discovered.count ?? 0

        let went = simulation.sendScouts()
        #expect(went)
        for _ in 0...(simulation.config.scoutDays) { simulation.stepDay() }

        #expect(simulation.scoutsOut == false)
        for chunk in expected {
            #expect(simulation.terrain?.hasDiscovered(chunk) == true)
        }
        #expect((simulation.terrain?.discovered.count ?? 0) >= known + expected.count)
    }

    @Test("A party in the field costs the day's foraging")
    func scoutsCostForaging() {
        var withParty = Fixture.thrivingSimulation(patches: 6, distance: 300, seed: 4)
        var without = Fixture.thrivingSimulation(patches: 6, distance: 300, seed: 4)

        withParty.world.scoutingParty = ScoutingParty(leftOnDay: 0, returnsOnDay: 30)
        for _ in 0..<10 {
            withParty.stepDay()
            without.stepDay()
        }
        #expect(withParty.world.history.samples.count == without.world.history.samples.count)
        #expect(
            withParty.hive.resources[.honey] < without.hive.resources[.honey],
            "a tenth of the foragers away should show in the larder"
        )
    }

    // MARK: - Biomes on threats and disease

    @Test("Each biome's own animals are the likelier ones there")
    func predatorTablesFavourTheirGround() {
        #expect(Biome.woodland.predatorMultiplier(for: .badger) > 1.4)
        #expect(Biome.village.predatorMultiplier(for: .badger) < 0.8)
        #expect(Biome.village.predatorMultiplier(for: .wasp) > 1.4)
        #expect(Biome.heath.predatorMultiplier(for: .bear) > 1.4)
        #expect(Biome.woodland.predatorMultiplier(for: .bear) < 0.8)

        // Every biome names somebody, and nobody is named everywhere.
        for biome in Biome.allCases {
            let named = Predator.allCases.filter { biome.predatorMultiplier(for: $0) > 1 }
            #expect(!named.isEmpty, "\(biome.rawValue) has nothing hunting in it")
            #expect(named.count < Predator.allCases.count / 2)
        }
    }

    @Test("Wet ground is nosema country; varroa is nobody's")
    func pathogenTablesFollowTheGround() {
        #expect(Biome.riverbank.pathogenMultiplier(for: .nosema) > 1.4)
        #expect(Biome.heath.pathogenMultiplier(for: .nosema) < 1)
        #expect(Biome.woodland.pathogenMultiplier(for: .chalkbrood) > 1.4)

        for biome in Biome.allCases {
            #expect(biome.pathogenMultiplier(for: .varroa) == 1)
        }
    }

    @Test("biomeThreatScale of zero is the engine before biomes existed")
    func scaleZeroIsNeutral() {
        var config = SimulationConfig.standard
        config.biomeThreatScale = 0
        for biome in Biome.allCases {
            for predator in Predator.allCases {
                #expect(config.scaled(biome.predatorMultiplier(for: predator)) == 1)
            }
            for pathogen in Pathogen.allCases {
                #expect(config.scaled(biome.pathogenMultiplier(for: pathogen)) == 1)
            }
        }

        var doubled = SimulationConfig.standard
        doubled.biomeThreatScale = 2
        #expect(doubled.scaled(1.5) == 2.0)
        #expect(doubled.scaled(0.6) > 0)
    }

    /// The hook itself, isolated: only `ThreatSystem` runs, so the colony is
    /// the same colony on both grounds and the only thing that can differ is
    /// the table.
    @Test("The threat hook actually reads the biome")
    func threatHookReadsTheBiome() {
        func attacks(on biome: Biome, scale: Double) -> Int {
            var config = SimulationConfig.standard
            config.biomeThreatScale = scale

            var simulation = Simulation.newGame(
                at: HiveLocation(type: .livingTreeCavity),
                startingAt: epoch, config: config, seed: 11
            )
            simulation.setTerrainBiome(biome)

            var world = simulation.world
            var clock = SimClock(epoch: epoch)
            var rng = SeededRandom(seed: 5)
            var ids = IDGenerator(startingAt: 500_000)
            let system = ThreatSystem()
            var total = 0

            // The clock has to actually run: a siege only ends on a later day,
            // and a frozen calendar would count one attack and then nothing.
            for _ in 0..<600 {
                var context = TickContext(clock: clock, config: config, rng: rng, ids: ids)
                system.updateDaily(&world, &context)
                rng = context.rng
                ids = context.ids
                total += context.events.filter {
                    if case .attacked = $0 { return true }
                    if case .threatBegan = $0 { return true }
                    return false
                }.count
                for _ in 0..<SimClock.ticksPerDay { clock.commitTick() }
            }
            return total
        }

        #expect(attacks(on: .village, scale: 1) != attacks(on: .woodland, scale: 1))
        #expect(attacks(on: .village, scale: 0) == attacks(on: .woodland, scale: 0))
    }

    /// And the disease hook, the same way.
    @Test("The disease hook actually reads the biome")
    func diseaseHookReadsTheBiome() {
        func infections(on biome: Biome, scale: Double) -> Int {
            var config = SimulationConfig.standard
            config.biomeThreatScale = scale
            // Turned right up, so a few hundred days is enough to separate two
            // grounds without running a decade.
            config.pathogenArrivalMultiplier = 40

            var simulation = Simulation.newGame(
                at: HiveLocation(type: .livingTreeCavity),
                startingAt: epoch, config: config, seed: 12
            )
            simulation.setTerrainBiome(biome)

            var count = 0
            let system = DiseaseSystem()
            for round in 0..<300 {
                var world = simulation.world
                var context = TickContext(
                    clock: SimClock(epoch: epoch), config: config,
                    rng: SeededRandom(seed: UInt64(round) &+ 3),
                    ids: IDGenerator(startingAt: 500_000)
                )
                system.updateDaily(&world, &context)
                count += context.events.filter {
                    if case .infectionDetected = $0 { return true }
                    return false
                }.count
            }
            return count
        }

        #expect(infections(on: .riverbank, scale: 1) != infections(on: .heath, scale: 1))
        #expect(infections(on: .riverbank, scale: 0) == infections(on: .heath, scale: 0))
    }

    // MARK: - Directions

    @Test("The six directions are named the way the lattice runs")
    func directionsAreNamed() {
        let origin = HexCoordinate.origin
        #expect(origin.direction(to: HexCoordinate(q: 4, r: 0)) == "east")
        #expect(origin.direction(to: HexCoordinate(q: 0, r: 4)) == "south-east")
        #expect(origin.direction(to: HexCoordinate(q: -4, r: 4)) == "south-west")
        #expect(origin.direction(to: HexCoordinate(q: -4, r: 0)) == "west")
        #expect(origin.direction(to: HexCoordinate(q: 0, r: -4)) == "north-west")
        #expect(origin.direction(to: HexCoordinate(q: 4, r: -4)) == "north-east")
        #expect(origin.direction(to: origin) == nil)
    }

    @Test("Every named direction is one of the six")
    func directionsAreAlwaysOfTheSix() {
        for q in -12...12 {
            for r in -12...12 {
                let cell = HexCoordinate(q: q, r: r)
                guard let name = HexCoordinate.origin.direction(to: cell) else {
                    #expect(cell == .origin)
                    continue
                }
                #expect(HexCoordinate.compassNames.contains(name))
            }
        }
    }

    // MARK: - Old saves

    @Test("A save written before the country opens, and gets one")
    func oldSavesStillDecode() throws {
        // A world encoded without any of Phase 2's fields, which is what every
        // save on a phone today looks like.
        var original = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 3
        )
        original.world.terrain = nil
        original.world.removeWildPatches()

        let data = try JSONEncoder().encode(original)
        var decoded = try JSONDecoder().decode(Simulation.self, from: data)

        #expect(decoded.terrain == nil)
        #expect(decoded.world.scoutingParty == nil)
        #expect(decoded.world.exploringToday == false)

        let adopted = decoded.adoptTerrainIfMissing()
        #expect(adopted)
        #expect(decoded.terrain != nil)
        let gotCountry = decoded.wildPatches.isEmpty == false
        #expect(gotCountry, "a migrated colony gets its country")
        let again = decoded.adoptTerrainIfMissing()
        #expect(again == false, "and only once")
    }

    @Test("Changing the ground takes the old country's hedges with it")
    func changingSeedReplantsTheCountry() {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 2026
        )
        simulation.registerPhotograph(
            photoLocalIdentifier: "mine", species: Fixture.clover,
            confidence: 0.9, takenAt: epoch
        )

        let before = simulation.wildPatches.map(\.photoLocalIdentifier)
        simulation.setTerrainSeed(4_242)
        let after = simulation.wildPatches.map(\.photoLocalIdentifier)

        #expect(before != after, "the hedges belong to the ground")
        #expect(simulation.patches.contains { $0.photoLocalIdentifier == "mine" },
                "the player's own flowers do not")
    }

    @Test("Asking for a biome gets that biome")
    func biomeSearchFindsGround() {
        for biome in Biome.allCases {
            var simulation = Simulation.newGame(
                at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 77
            )
            let found = simulation.setTerrainBiome(biome)
            #expect(found)
            #expect(simulation.homeChunk?.biome == biome)
        }
    }

    // MARK: - What the interface is handed

    @Test("The terrain summary carries the whole map and the rumours")
    func terrainSummaryCarriesTheCountry() {
        let simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity), startingAt: epoch, seed: 2026
        )
        let snapshot = simulation.snapshot()
        guard let terrain = snapshot.terrain else { Issue.record("no terrain"); return }

        #expect(terrain.discovered.count == 7)
        #expect(terrain.discovered.first?.coordinate == terrain.home.coordinate)
        #expect(terrain.rumoured == simulation.rumouredChunks)
        #expect(terrain.scoutsOut == false)
        #expect(terrain.scoutsDaysRemaining == nil)
        #expect(snapshot.scoutDecisionOpen == simulation.scoutDecisionOpen)

        // And it can say which parish a cell is in, for anything the colony
        // has been to and nothing it has not.
        let wild = simulation.wildPatches.first
        #expect(terrain.chunk(containing: wild?.cell ?? .origin) != nil)
        #expect(terrain.chunk(containing: HexCoordinate(q: 30, r: 0)) == nil)
    }
}
