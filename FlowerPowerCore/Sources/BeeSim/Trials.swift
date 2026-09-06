//
//  Trials.swift
//  BeeSim
//
//  Balance is a distribution, not a single run. One colony dying tells you
//  almost nothing — it may have met a bear. This runs the same scenario across
//  many seeds and reports what fraction survive, how big they get, and what
//  actually kills them, which is the only sound basis for tuning.
//

import Foundation
import FlowerPowerCore

struct TrialOutcome {
    var survived = false
    var daysSurvived = 0
    var peakPopulation = 0
    var finalPopulation = 0
    var peakHoney = 0.0
    var winterStoresAtAutumnEnd = 0.0
    var winterCluster = 0
    /// Day the colony first fell below a viable workforce — the moment it was
    /// effectively finished, as opposed to the day the last bee died.
    var dayOfCollapse: Int?
    var seasonOfCollapse: Season?
    var swarms = 0
    var queenLosses = 0
    var supersedures = 0
    var matingFailures = 0
    var emergencyCells = 0
    var queensEmerged = 0
    var queensMated = 0
    var queenDeaths: [DeathCause: Int] = [:]
    var deaths: [DeathCause: Int] = [:]

    /// Best single explanation for the colony's death, inferred from what
    /// killed the most bees plus the colony-level events.
    var causeOfDeath: String = "survived"
}

enum Trials {

    static func run(
        trials: Int,
        days: Int,
        patches: Int,
        distance: Double,
        restockEvery: Int,
        config: SimulationConfig,
        site: HiveLocationType,
        palette: [FlowerSpecies],
        start: Date,
        shared: Bool = false
    ) -> [TrialOutcome] {

        (0..<trials).map { trial in
            var simulation = Simulation.newGame(
                at: HiveLocation(type: site),
                startingAt: start,
                config: config,
                seed: UInt64(1_000 + trial * 7_919)
            )

            func stock(_ count: Int, tag: String) {
                for index in 0..<count {
                    if shared {
                        simulation.importSharedFlower(
                            shareID: "\(tag)-\(index)",
                            photoLocalIdentifier: "\(tag)-\(index)",
                            species: palette[index % palette.count],
                            confidence: 0.9,
                            coordinate: nil,
                            takenAt: start,
                            sharedBy: "a friend",
                            distanceMetres: distance
                        )
                    } else {
                        simulation.registerPhotograph(
                            photoLocalIdentifier: "\(tag)-\(index)",
                            species: palette[index % palette.count],
                            confidence: 0.9,
                            coordinate: nil,
                            takenAt: start,
                            distanceMetres: distance
                        )
                    }
                }
            }

            stock(patches, tag: "t\(trial)")

            var outcome = TrialOutcome()
            var layingWorkers = false
            var absconded = false
            var starvedRecently = false

            for day in 0..<days {
                for event in simulation.stepDay() {
                    switch event {
                    case .died(let kind, let cause):
                        outcome.deaths[cause, default: 0] += 1
                        if kind == .queen { outcome.queenDeaths[cause, default: 0] += 1 }
                    case .swarmed: outcome.swarms += 1
                    case .queenLost: outcome.queenLosses += 1
                    case .supersededQueen: outcome.supersedures += 1
                    case .matingFlightFailed: outcome.matingFailures += 1
                    case .queenEmerged: outcome.queensEmerged += 1
                    case .queenMated: outcome.queensMated += 1
                    case .queenCellStarted(let purpose):
                        if purpose == .emergency { outcome.emergencyCells += 1 }
                    case .layingWorkersAppeared: layingWorkers = true
                    case .absconded: absconded = true
                    case .starving: starvedRecently = true
                    default: break
                    }
                }

                outcome.peakPopulation = max(outcome.peakPopulation, simulation.hive.population)
                outcome.peakHoney = max(outcome.peakHoney, simulation.hive.resources[.honey])

                // Snapshot the stores at the last moment they can still matter.
                if Season(day: simulation.day) == .autumn, Season.progress(simulation.day) > 0.95 {
                    outcome.winterStoresAtAutumnEnd = simulation.hive.resources.edibleEnergy
                    outcome.winterCluster = simulation.hive.adultCount
                }

                if restockEvery > 0, day % restockEvery == 0, day > 0 {
                    simulation.pruneDepletedPatches()
                    stock(max(1, patches / 3), tag: "t\(trial)d\(day)")
                }

                outcome.daysSurvived = day

                if outcome.dayOfCollapse == nil, simulation.hive.adultWorkerCount <= 5, day > 20 {
                    outcome.dayOfCollapse = day
                    outcome.seasonOfCollapse = Season(day: simulation.day)
                }

                if simulation.hive.bees.isEmpty { break }
            }

            outcome.survived = !simulation.hive.bees.isEmpty && simulation.hive.adultWorkerCount > 5
            outcome.finalPopulation = simulation.hive.population

            // Attribute by the state the colony actually died in, not by
            // anything that ever happened to it. Labelling every colony that
            // once lost a queen as "queen failure" hid the real cause: most had
            // requeened successfully and then starved months later.
            let snapshot = simulation.snapshot()

            if outcome.survived {
                outcome.causeOfDeath = "survived"
            } else if absconded {
                outcome.causeOfDeath = "absconded"
            } else if layingWorkers || snapshot.queen.state == .layingWorkers {
                outcome.causeOfDeath = "laying workers"
            } else if snapshot.queen.state == .absent {
                outcome.causeOfDeath = "queenless"
            } else if snapshot.queen.state == .droneLayer || snapshot.queen.state == .virgin {
                outcome.causeOfDeath = "queen unmated"
            } else if snapshot.stores.edibleEnergy < 20 || starvedRecently {
                outcome.causeOfDeath = "starvation"
            } else if (outcome.deaths[.disease] ?? 0) > 20 {
                outcome.causeOfDeath = "disease"
            } else if (outcome.deaths[.predation] ?? 0) > 40 {
                outcome.causeOfDeath = "predation"
            } else {
                outcome.causeOfDeath = "dwindled"
            }

            return outcome
        }
    }

    static func report(_ outcomes: [TrialOutcome], days: Int) {
        let survived = outcomes.filter(\.survived)
        let rate = Double(survived.count) / Double(max(1, outcomes.count))

        func mean(_ values: [Double]) -> Double {
            values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        }
        func median(_ values: [Int]) -> Int {
            guard !values.isEmpty else { return 0 }
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }

        print("")
        print(String(repeating: "=", count: 62))
        print("TRIALS  \(outcomes.count) colonies x \(days) days")
        print(String(repeating: "=", count: 62))
        print(String(format: "Survival rate:        %.0f%%  (%d of %d)",
                     rate * 100, survived.count, outcomes.count))
        print("Median peak pop:      \(median(outcomes.map(\.peakPopulation)))")
        let collapses = outcomes.compactMap(\.dayOfCollapse)
        if !collapses.isEmpty {
            print("Median day of collapse: \(median(collapses))")
        }
        print(String(format: "Mean peak honey:      %.0f", mean(outcomes.map(\.peakHoney))))
        print(String(format: "Mean autumn stores:   %.0f", mean(outcomes.map(\.winterStoresAtAutumnEnd))))
        print("Median winter cluster: \(median(outcomes.map(\.winterCluster)))")
        print(String(format: "Mean swarms:          %.2f", mean(outcomes.map { Double($0.swarms) })))
        print(String(format: "Mean queen losses:    %.2f", mean(outcomes.map { Double($0.queenLosses) })))
        print(String(format: "Mean supersedures:    %.2f", mean(outcomes.map { Double($0.supersedures) })))
        print(String(format: "Mean emergency cells: %.2f", mean(outcomes.map { Double($0.emergencyCells) })))
        print(String(format: "Mean queens emerged:  %.2f", mean(outcomes.map { Double($0.queensEmerged) })))
        print(String(format: "Mean queens mated:    %.2f", mean(outcomes.map { Double($0.queensMated) })))
        print(String(format: "Mean mating failures: %.2f", mean(outcomes.map { Double($0.matingFailures) })))

        print("")
        print("Cause of death:")
        let causes = Dictionary(grouping: outcomes, by: \.causeOfDeath)
            .mapValues(\.count)
            .sorted { $0.value > $1.value }
        for (cause, count) in causes {
            let bar = String(repeating: "#", count: count * 40 / max(1, outcomes.count))
            print("  " + pad(cause, 16) + padLeft("\(count)", 4) + "  " + bar)
        }

        print("")
        print("Queen deaths by cause (mean per colony):")
        var queenTotals: [DeathCause: Int] = [:]
        for outcome in outcomes {
            for (cause, count) in outcome.queenDeaths { queenTotals[cause, default: 0] += count }
        }
        for (cause, total) in queenTotals.sorted(by: { $0.value > $1.value }) {
            let perColony = Double(total) / Double(max(1, outcomes.count))
            print("  " + pad(cause.displayName, 18) + padLeft(String(format: "%.2f", perColony), 6))
        }

        print("")
        print("Season of collapse:")
        let seasons = Dictionary(grouping: outcomes.compactMap(\.seasonOfCollapse), by: { $0 })
            .mapValues(\.count)
            .sorted { $0.value > $1.value }
        for (season, count) in seasons {
            let bar = String(repeating: "#", count: count * 40 / max(1, outcomes.count))
            print("  " + pad(season.rawValue, 16) + padLeft("\(count)", 4) + "  " + bar)
        }

        print("")
        print("Deaths by cause (mean per colony):")
        var totals: [DeathCause: Int] = [:]
        for outcome in outcomes {
            for (cause, count) in outcome.deaths { totals[cause, default: 0] += count }
        }
        for (cause, total) in totals.sorted(by: { $0.value > $1.value }) {
            let perColony = Double(total) / Double(max(1, outcomes.count))
            print("  " + pad(cause.displayName, 18) + padLeft(String(format: "%.0f", perColony), 6))
        }
    }
}
