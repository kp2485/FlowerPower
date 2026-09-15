import Testing
import Foundation
@testable import FlowerPowerCore

/// The garden as a place: flowers planted in cells, at distances that follow
/// from where they were put.
///
/// Until now every patch in the game stood at the nominal 800 m and always
/// had, because the only proposed source of a distance was a hive coordinate
/// the engine never received. These are the tests that say the lever is
/// actually connected.
@Suite("The garden")
struct GardenTests {

    private func colony(seed: UInt64 = 42) -> Simulation {
        Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity),
            startingAt: epoch,
            seed: seed
        )
    }

    // MARK: - Founding

    @Test("A new colony is founded with a world around it")
    func newGameHasTerrain() {
        let terrain = colony().terrain

        #expect(terrain?.home == .origin)
        #expect(terrain?.gardenRings == 1)
        // The home chunk and the six around it: a founding swarm's scouts have
        // been over that much already.
        #expect(terrain?.discovered.count == 7)
        #expect(terrain?.discovered.first == .origin)
        #expect(Array(terrain?.discovered.dropFirst() ?? []) == ChunkCoordinate.origin.neighbours)
    }

    @Test("The world seed follows the colony seed but is not it")
    func terrainSeedIsDerived() {
        let one = colony(seed: 1)
        let same = colony(seed: 1)
        let other = colony(seed: 2)

        #expect(one.terrain?.seed == same.terrain?.seed)
        #expect(one.terrain?.seed != other.terrain?.seed)
        #expect(one.terrain?.seed != 1)
    }

    // MARK: - Planting

    @Test("Photographs fill the garden in ring order, at 200 metres")
    func photographsArePlantedInRingOrder() {
        var simulation = colony()
        let expected = HexCoordinate.origin.ring(radius: 1)

        for index in 0..<6 {
            let patch = simulation.registerPhotograph(
                photoLocalIdentifier: "p\(index)",
                species: Fixture.clover,
                confidence: 0.9,
                takenAt: epoch
            )
            #expect(patch.cell == expected[index])
            #expect(patch.distanceMetres == 200)
        }

        #expect(simulation.terrain?.gardenRings == 1)
    }

    @Test("A full garden opens the next ring rather than refusing a flower")
    func fullGardenGrows() {
        var simulation = colony()
        for index in 0..<6 {
            simulation.registerPhotograph(
                photoLocalIdentifier: "p\(index)", species: Fixture.clover,
                confidence: 0.9, takenAt: epoch
            )
        }
        #expect(simulation.terrain?.gardenRings == 1)

        let seventh = simulation.registerPhotograph(
            photoLocalIdentifier: "p6", species: Fixture.clover,
            confidence: 0.9, takenAt: epoch
        )

        #expect(simulation.terrain?.gardenRings == 2)
        #expect(seventh.cell == HexCoordinate.origin.ring(radius: 2).first)
        #expect(seventh.distanceMetres == 400)
    }

    @Test("A shared flower is planted in the garden like any other")
    func sharedFlowersArePlanted() {
        var simulation = colony()
        let patch = simulation.importSharedFlower(
            shareID: "s1", photoLocalIdentifier: "s1", species: Fixture.heather,
            confidence: 0.9, takenAt: epoch, sharedBy: "a friend"
        )
        #expect(patch?.cell == HexCoordinate.origin.ring(radius: 1).first)
        #expect(patch?.distanceMetres == 200)
    }

    @Test("An explicit distance wins, and suppresses placement entirely")
    func explicitDistanceWins() {
        var simulation = colony()
        let patch = simulation.registerPhotograph(
            photoLocalIdentifier: "far", species: Fixture.clover,
            confidence: 0.9, takenAt: epoch, distanceMetres: 1_600
        )

        #expect(patch.distanceMetres == 1_600)
        // No cell at all, so the garden is untouched and the next photograph
        // still gets the innermost cell. This is what holds a whole `beesim`
        // sweep at one distance.
        #expect(patch.cell == nil)
        #expect(simulation.terrain?.gardenRings == 1)

        let next = simulation.registerPhotograph(
            photoLocalIdentifier: "near", species: Fixture.clover,
            confidence: 0.9, takenAt: epoch
        )
        #expect(next.cell == HexCoordinate.origin.ring(radius: 1).first)
    }

    @Test("A colony with no world plants nothing and stands at the nominal distance")
    func noWorldNoPlacement() {
        var simulation = colony()
        simulation.mutateWorld { $0.terrain = nil }

        let patch = simulation.registerPhotograph(
            photoLocalIdentifier: "p", species: Fixture.clover,
            confidence: 0.9, takenAt: epoch
        )
        #expect(patch.cell == nil)
        #expect(patch.distanceMetres == FlowerPatch.nominalDistance)
    }

    @Test("A patch that has faded gives its cell back")
    func fadedPatchReleasesItsCell() {
        var simulation = colony()
        let first = simulation.registerPhotograph(
            photoLocalIdentifier: "old", species: Fixture.clover,
            confidence: 0.9, takenAt: epoch
        )
        let cell = first.cell ?? .origin

        // Past fresh and all the way through the fade.
        let gone = simulation.config.patchFreshDays + simulation.config.patchFadeDays + 1
        simulation.setDay(gone)
        #expect(simulation.patches[0].hasFaded(onDay: simulation.day, config: simulation.config))
        #expect(simulation.isCellOccupied(cell) == false)

        let replacement = simulation.registerPhotograph(
            photoLocalIdentifier: "new", species: Fixture.clover,
            confidence: 0.9, takenAt: epoch
        )
        #expect(replacement.cell == cell)
        #expect(simulation.terrain?.gardenRings == 1)
    }

    // MARK: - Moving a flower

    @Test("Planting moves a patch and its distance together")
    func plantMovesTheDistanceToo() {
        var simulation = colony()
        let patch = simulation.registerPhotograph(
            photoLocalIdentifier: "p", species: Fixture.clover,
            confidence: 0.9, takenAt: epoch
        )
        #expect(patch.distanceMetres == 200)

        let outer = HexCoordinate(q: 3, r: 0)
        let moved = simulation.plant(patch.id, at: outer)
        #expect(moved)
        #expect(simulation.patches[0].cell == outer)
        #expect(simulation.patches[0].distanceMetres == 600)
    }

    @Test("Planting refuses a cell something is already standing in")
    func plantRefusesAnOccupiedCell() {
        var simulation = colony()
        let first = simulation.registerPhotograph(
            photoLocalIdentifier: "a", species: Fixture.clover,
            confidence: 0.9, takenAt: epoch
        )
        let second = simulation.registerPhotograph(
            photoLocalIdentifier: "b", species: Fixture.clover,
            confidence: 0.9, takenAt: epoch
        )

        let occupied = first.cell ?? .origin
        let refused = simulation.plant(second.id, at: occupied)
        #expect(refused == false)
        #expect(simulation.patches[1].cell == second.cell)

        // And an unknown patch is a no-op rather than a trap.
        let unknown = simulation.plant(EntityID(rawValue: 999_999), at: HexCoordinate(q: 9, r: 0))
        #expect(unknown == false)
    }

    // MARK: - Milestones

    @Test("Ten flowers opens the second ring and ten families the third")
    func milestonesOpenTheGarden() {
        var ids = IDGenerator()
        var world = World(hive: Hive.newColony(
            at: HiveLocation(type: .livingTreeCavity), ids: &ids
        ))
        world.terrain = Terrain(seed: 7)
        #expect(world.terrain?.gardenRings == 1)

        // Awarded directly rather than simulated into: the hook under test is
        // what `MilestoneSystem` does *after* `award` returns true.
        _ = world.milestones.award(.tenFlowers, onDay: 10)
        MilestoneSystem.openGarden(for: .tenFlowers, &world)
        #expect(world.terrain?.gardenRings == 2)

        _ = world.milestones.award(.tenFamilies, onDay: 20)
        MilestoneSystem.openGarden(for: .tenFamilies, &world)
        #expect(world.terrain?.gardenRings == 3)

        // And it never takes ground away from a garden that has already grown.
        MilestoneSystem.openGarden(for: .tenFlowers, &world)
        #expect(world.terrain?.gardenRings == 3)
    }

    // MARK: - Identification

    @Test("Identifying a patch keeps everything the patch already was")
    func identifyPreservesTheRecord() {
        var simulation = colony()
        let original = simulation.importSharedFlower(
            shareID: "gift", photoLocalIdentifier: "gift",
            species: nil, confidence: 0, takenAt: epoch, sharedBy: "Ada"
        )

        // A hundred days later somebody finally works out what it was.
        simulation.setDay(100)
        let vigourBefore = simulation.patches[0].vigour(
            onDay: 100, config: simulation.config
        )
        simulation.identifyPatch(original?.id ?? .unassigned, as: Fixture.heather, confidence: 0.95)

        let patch = simulation.patches[0]
        #expect(patch.species?.id == FlowerCatalogue.heather.id)
        // The photograph was taken when it was taken.
        #expect(patch.registeredOnDay == 0)
        #expect(patch.vigour(onDay: 100, config: simulation.config) == vigourBefore)
        #expect(patch.origin == .shared)
        #expect(patch.sharedBy == "Ada")
        #expect(patch.cell == original?.cell)
        #expect(patch.distanceMetres == original?.distanceMetres)
    }

    // MARK: - Presentation

    @Test("The snapshot carries the world and the garden, ready to draw")
    func snapshotCarriesTerrain() {
        var simulation = colony()
        let planted = simulation.registerPhotograph(
            photoLocalIdentifier: "p", species: Fixture.clover,
            confidence: 0.9, takenAt: epoch
        )

        let terrain = simulation.snapshot().terrain
        let snapshot = simulation.snapshot()

        #expect(terrain?.gardenRings == 1)
        #expect(terrain?.garden.count == 6)
        #expect(terrain?.neighbours.count == 6)
        #expect(terrain?.home.coordinate == .origin)
        #expect(terrain?.homeName.isEmpty == false)

        // Ring order, and the first cell holds the flower.
        #expect(terrain?.garden.map(\.cell) == HexCoordinate.origin.ring(radius: 1))
        #expect(terrain?.garden.first?.patchID == planted.id)
        #expect(terrain?.garden.first?.distanceMetres == 200)
        #expect(terrain?.garden.first?.ring == 1)
        #expect(terrain?.emptyCells.count == 5)

        #expect(snapshot.patches.first?.cell == planted.cell)
    }

    @Test("A colony with no world has no terrain on its snapshot")
    func snapshotWithoutTerrain() {
        var simulation = colony()
        simulation.mutateWorld { $0.terrain = nil }
        #expect(simulation.snapshot().terrain == nil)
    }

    // MARK: - Determinism

    @Test("The world does not disturb the colony's determinism")
    func determinismHolds() {
        var a = colony(seed: 99)
        var b = colony(seed: 99)

        for index in 0..<8 {
            a.registerPhotograph(
                photoLocalIdentifier: "p\(index)", species: Fixture.palette[index % 6],
                confidence: 0.9, takenAt: epoch
            )
            b.registerPhotograph(
                photoLocalIdentifier: "p\(index)", species: Fixture.palette[index % 6],
                confidence: 0.9, takenAt: epoch
            )
        }

        a.runDays(30)
        b.runDays(30)
        #expect(a == b, "identical seeds diverged with the world on")
    }

    @Test("Catch-up in a world matches living through it")
    func catchUpMatchesLivePlay() {
        var live = colony(seed: 5)
        var offline = colony(seed: 5)
        for index in 0..<8 {
            live.registerPhotograph(
                photoLocalIdentifier: "p\(index)", species: Fixture.palette[index % 6],
                confidence: 0.9, takenAt: epoch
            )
            offline.registerPhotograph(
                photoLocalIdentifier: "p\(index)", species: Fixture.palette[index % 6],
                confidence: 0.9, takenAt: epoch
            )
        }

        live.runDays(21)
        offline.advance(to: .afterSimulated(days: 21))
        #expect(live == offline, "offline catch-up diverged with the world on")
    }

    @Test("Terrain survives a round trip through the save format")
    func terrainRoundTrips() throws {
        var simulation = colony()
        simulation.registerPhotograph(
            photoLocalIdentifier: "p", species: Fixture.clover,
            confidence: 0.9, takenAt: epoch
        )
        simulation.registerPhotograph(
            photoLocalIdentifier: "q", species: Fixture.heather,
            confidence: 0.9, takenAt: epoch
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(
            Simulation.self, from: try encoder.encode(simulation)
        )

        #expect(restored == simulation)
        #expect(restored.terrain?.seed == simulation.terrain?.seed)
        #expect(restored.patches.map(\.cell) == simulation.patches.map(\.cell))
    }
}
