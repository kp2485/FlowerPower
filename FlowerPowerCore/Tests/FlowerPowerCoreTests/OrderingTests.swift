import Testing
import Foundation
@testable import FlowerPowerCore

/// The simulation must give the same answer twice, in two different processes.
///
/// It did not. Two identical `beesim --trials 60 --days 730` runs returned 30%
/// and 33% two-year survival — three colonies of difference, from the same
/// seeds, the same binary and the same arguments. The cause was Swift's
/// `Hasher`, which is seeded randomly once per process: every `Dictionary` in
/// the engine iterates in a different order in every run of the program.
///
/// That is harmless where a loop only reads. It is not harmless in
/// `DiseaseSystem.applyMortality`, which draws from the random stream once per
/// pathogen — so with two infections present, the order they were visited in
/// decided which of two RNG draws happened first, and the colony's entire
/// future forked there.
///
/// The fix is to iterate declaration order rather than hash order. These tests
/// hold that line. They cannot themselves observe two hash seeds — a process
/// gets one — so what they check is the property that makes the seed
/// irrelevant: that the ordered views are complete, stable, and in
/// `allCases` order regardless of how the underlying storage was built.
///
/// The end-to-end check is two `beesim` runs of the same arguments producing
/// byte-identical output. See PLAN.md section 4.
@Suite("Deterministic ordering")
struct OrderingTests {

    // MARK: - Infections

    @Test("Infections are visited in declaration order, however they were added")
    func pathogensAreOrdered() {
        // Two loads with the same contents, built in opposite orders. Within
        // one process these hash the same way, so this is not testing the hash
        // seed — it is testing that the accessor does not depend on it.
        let forwards = PathogenLoad([
            .varroa: 0.3, .nosema: 0.2, .deformedWingVirus: 0.1
        ])
        var backwards = PathogenLoad()
        backwards[.deformedWingVirus] = 0.1
        backwards[.nosema] = 0.2
        backwards[.varroa] = 0.3

        let expected = Pathogen.allCases.filter {
            [.varroa, .nosema, .deformedWingVirus].contains($0)
        }

        #expect(forwards.ordered.map(\.pathogen) == expected)
        #expect(backwards.ordered.map(\.pathogen) == expected)
    }

    @Test("The ordered view holds exactly what is present")
    func orderedIsComplete() {
        var load = PathogenLoad()
        load[.varroa] = 0.4
        load[.chalkbrood] = 0.1

        #expect(load.ordered.count == 2)
        #expect(load.ordered.map(\.level).reduce(0, +) == 0.5)
        // Cleared infections leave, rather than lingering at zero.
        load[.chalkbrood] = 0
        #expect(load.ordered.map(\.pathogen) == [.varroa])
    }

    /// A tie between two equally bad infections has to resolve the same way
    /// every run, or the alert the player sees changes at random.
    @Test("The dominant infection is stable under a tie")
    func dominantIsStable() {
        let load = PathogenLoad([.varroa: 0.25, .nosema: 0.25, .chalkbrood: 0.1])
        let answers = (0..<50).map { _ in load.dominant?.pathogen }
        #expect(Set(answers).count == 1, "dominant disagreed with itself")
        #expect(load.dominant?.level == 0.25)
    }

    /// Floating-point multiplication is not associative, so the order the
    /// survivals multiply in decides the last bits — and `totalPressure > 0.5`
    /// is a gate on colony status.
    @Test("Combined pressure does not depend on iteration order")
    func totalPressureIsStable() {
        let load = PathogenLoad([
            .varroa: 0.31, .nosema: 0.17, .deformedWingVirus: 0.23,
            .chalkbrood: 0.11, .americanFoulbrood: 0.07
        ])
        let answers = Set((0..<50).map { _ in load.totalPressure.bitPattern })
        #expect(answers.count == 1, "totalPressure was not bit-identical across reads")
    }

    // MARK: - Stores

    @Test("Stores are visited in declaration order")
    func resourcesAreOrdered() {
        var pool = ResourcePool()
        pool.add(10, of: .propolis)
        pool.add(20, of: .honey)
        pool.add(30, of: .nectar)

        let expected = ResourceKind.allCases.filter {
            [.honey, .nectar, .propolis].contains($0)
        }
        #expect(pool.ordered.map(\.kind) == expected)
    }

    /// `cellsOccupied` rounds up, so a last-bit difference in the sum becomes a
    /// whole cell — and free cells gate where the queen may lay.
    @Test("Cells occupied is stable across reads")
    func cellsOccupiedIsStable() {
        var pool = ResourcePool()
        pool.add(37.3, of: .honey)
        pool.add(11.7, of: .pollen)
        pool.add(5.9, of: .beeBread)
        pool.add(2.3, of: .nectar)

        let answers = Set((0..<50).map { _ in pool.cellsOccupied })
        #expect(answers.count == 1)
        #expect(pool.cellsOccupied > 0)
    }

    // MARK: - End to end

    /// Two colonies from the same seed, run side by side, must stay identical
    /// through a stretch long enough for disease to appear and kill.
    ///
    /// Within one process this cannot catch a hash-order bug on its own — both
    /// copies see the same seed — but it does catch anything else that has
    /// crept into the step, and it is the shape the cross-process check takes.
    @Test("The same seed gives the same colony")
    func sameSeedSameColony() {
        var left = Fixture.thrivingSimulation(config: .standard, seed: 4_242)
        var right = Fixture.thrivingSimulation(config: .standard, seed: 4_242)

        // Both start with two infections, so the mortality loop has more than
        // one pathogen to visit and the order can matter at all.
        let infect: (inout World) -> Void = { world in
            world.hive.pathogens[.varroa] = 0.22
            world.hive.pathogens[.nosema] = 0.18
        }
        left.mutateWorld(infect)
        right.mutateWorld(infect)

        for _ in 0..<200 {
            _ = left.stepDay()
            _ = right.stepDay()
        }

        #expect(left.hive.population == right.hive.population)
        #expect(left.hive.resources[.honey] == right.hive.resources[.honey])
        #expect(left.world.hive.pathogens.ordered.map(\.level)
                == right.world.hive.pathogens.ordered.map(\.level))
    }
}
