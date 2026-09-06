//
//  LineageSystem.swift
//  FlowerPowerCore
//
//  Keeps the line of queens from the events the other systems emit.
//
//  Last in the pipeline, deliberately: it reads what happened this tick and
//  writes the record, and never touches anything the other systems depend
//  on. Doing it here rather than at each emission site means the queen
//  systems do not have to know a lineage exists.
//

import Foundation

public struct LineageSystem: SimulationSystem {

    public init() {}

    public func update(_ world: inout World, _ context: inout TickContext) {
        for event in context.events {
            switch event {
            case .queenEmerged(let quality):
                // A supersedure or emergency queen emerging while the old
                // queen still reigns: the old one is ended when she actually
                // goes, which arrives as a separate event.
                world.lineage.crown(onDay: context.day, quality: quality)

            case .queenMated(let patrilines):
                world.lineage.mated(onDay: context.day, patrilines: patrilines)

            case .died(.queen, let cause):
                world.lineage.end(onDay: context.day, cause == .predation ? .predation : .oldAge)

            case .supersededQueen:
                // The mother has already been ended by her death event when
                // supersedure is by death; when it is by the colony's choice
                // she is ended here.
                endMother(&world, context.day, .superseded)

            case .matingFlightFailed:
                world.lineage.end(onDay: context.day, .matingFailed)

            case .queenLost:
                world.lineage.end(onDay: context.day, .lost)

            case .swarmed:
                // The reigning queen has left with the swarm. Her record is
                // carried by `DepartedSwarm` in case the player follows her.
                world.lineage.end(onDay: context.day, .leftWithSwarm)

            case .colonyCollapsed:
                world.lineage.end(onDay: context.day, .colonyEnded)

            default:
                break
            }
        }

        reconcile(&world, context.day)
    }

    /// The record can never show more reigning queens than the hive holds.
    ///
    /// Every way the engine loses a queen emits an event, but the hive is a
    /// plain value and a queen can be removed from it directly — a test does,
    /// and a future system might. Whoever is missing is recorded as lost on
    /// the day the record noticed, eldest first, since a mother who vanished
    /// without a word is the likelier absence than a daughter who has just
    /// emerged.
    private func reconcile(_ world: inout World, _ day: Int) {
        var reigning = world.lineage.queens.filter(\.isReigning).map(\.number)
        let present = world.hive.count(kind: .queen)
        while reigning.count > present, let eldest = reigning.first {
            world.lineage.endQueen(number: eldest, onDay: day, .lost)
            reigning.removeFirst()
        }
    }

    /// When a daughter has emerged and the mother is superseded, two records
    /// are open. The elder is the one being ended.
    private func endMother(_ world: inout World, _ day: Int, _ ending: QueenRecord.Ending) {
        let open = world.lineage.queens.filter(\.isReigning)
        guard open.count >= 2, let mother = open.first else {
            world.lineage.end(onDay: day, ending)
            return
        }
        world.lineage.endQueen(number: mother.number, onDay: day, ending)
    }
}
