//
//  main.swift
//  BeeSim
//
//  Headless balance tooling. Runs a colony for a chosen number of simulated
//  days and prints its trajectory, so tuning is driven by observed behaviour
//  rather than by guessing at constants.
//
//  Usage:
//    beesim [--days N] [--patches N] [--distance M] [--seed N]
//           [--preset standard|gentle|harsh] [--site <name>] [--every N]
//           [--world] [--world-seed N] [--biome <name>]
//
//  `--world` founds a generated countryside around the colony and plants
//  every stocked flower in the garden — 200 m in the first ring, 400 in the
//  second — instead of holding them all at `--distance`. Without it there is
//  no wild forage and no fog, and nothing about a run differs from one made
//  before the world existed, which is the property the whole of Phase 1 was
//  checked against and the reason every recorded baseline is still readable.
//
//  Since Phase 2 it also stocks the six parishes around the home chunk with
//  wild flowers, so `--world --patches 0` is a colony on wild forage alone —
//  the measurement `docs/WORLD.md` section 10 item 2 exists for. `--biome
//  <name>` puts a particular kind of ground under the nest, which is how the
//  survival-by-biome table is taken.
//

import Foundation
import FlowerPowerCore

// MARK: - Arguments

struct Options {
    var days = 365
    var patches = 12
    var distance = 400.0
    var seed: UInt64 = 42
    var preset = "standard"
    var site = "livingTreeCavity"
    var every = 15
    var restockEvery = 0
    var trials = 0
    var policy = "instinct"

    /// Model a player who is fed by other people rather than going out
    /// themselves: every restock arrives as a shared flower.
    var sharedForage = false

    /// Run in the generated world: the colony founds a terrain from its own
    /// seed and every stocked flower is planted into a garden cell instead of
    /// standing at a flat `--distance`. Off by default, and off is
    /// byte-identical to every run made before the world existed.
    var world = false

    /// Put every trial on the same countryside, so the spread between rows is
    /// the colony rather than the ground.
    var worldSeed: UInt64?

    /// Force the ground under the nest. Each trial still gets its own
    /// neighbours, so the row measures the biome rather than one map.
    var biome: String?

    /// Ad-hoc config overrides, so a knob can be swept without a rebuild.
    /// `--set pheromoneDilutionScale=45 --set swarmCongestionThreshold=0.55`
    var overrides: [String: Double] = [:]

    static func parse(_ arguments: [String]) -> Options {
        var options = Options()
        var index = 0

        while index < arguments.count {
            let flag = arguments[index]
            let value = index + 1 < arguments.count ? arguments[index + 1] : nil

            switch flag {
            case "--days": options.days = Int(value ?? "") ?? options.days
            case "--patches": options.patches = Int(value ?? "") ?? options.patches
            case "--distance": options.distance = Double(value ?? "") ?? options.distance
            case "--seed": options.seed = UInt64(value ?? "") ?? options.seed
            case "--preset": options.preset = value ?? options.preset
            case "--site": options.site = value ?? options.site
            case "--every": options.every = Int(value ?? "") ?? options.every
            case "--restock": options.restockEvery = Int(value ?? "") ?? options.restockEvery
            case "--trials": options.trials = Int(value ?? "") ?? options.trials
            case "--policy": options.policy = value ?? options.policy
            case "--world-seed": options.worldSeed = UInt64(value ?? "") ?? options.worldSeed
            case "--biome": options.biome = value ?? options.biome
            case "--shared":
                options.sharedForage = true
                index += 1
                continue
            case "--world":
                options.world = true
                index += 1
                continue
            case "--list":
                index += 1
                continue
            case "--set":
                let parts = (value ?? "").split(separator: "=", maxSplits: 1)
                if parts.count == 2, let number = Double(parts[1]) {
                    options.overrides[String(parts[0])] = number
                }
            default: break
            }
            index += 2
        }
        return options
    }

    var config: SimulationConfig {
        var config: SimulationConfig
        switch preset {
        case "gentle": config = .gentle
        case "harsh": config = .harsh
        default: config = .standard
        }

        // `--world` off means no country, and that is the whole point of the
        // flag: every balance number recorded in `PLAN.md` was taken on an
        // engine that had none, and a run that quietly grew forty hedges
        // around the nest would not be comparable with any of them. The app
        // always has a world — `newGame` always makes one — so this is a
        // statement about the tool rather than about the game.
        //
        // Before the overrides, so `--set wildPatchDensity=` still wins for
        // anyone who wants to sweep it with the garden held at one distance.
        if !world { config.wildPatchDensity = 0 }

        for (key, value) in overrides {
            config.apply(key, value)
        }
        return config
    }

    /// An unknown biome is a hard error for the same reason an unknown
    /// `--policy` is: a survival-by-biome sweep whose rows all quietly ran on
    /// whatever the seed gave is worse than no table at all.
    var homeBiome: Biome? {
        guard let biome else { return nil }
        guard let parsed = Biome(rawValue: biome) else {
            let known = Biome.allCases.map(\.rawValue).joined(separator: ", ")
            print("unknown --biome '\(biome)'. Known: \(known)")
            exit(2)
        }
        return parsed
    }

    var locationType: HiveLocationType {
        HiveLocationType(rawValue: site) ?? .livingTreeCavity
    }

    /// An unknown policy is a hard error for the same reason an unknown
    /// `--set` key is: a sweep whose rows all secretly ran the same thing is
    /// worse than no measurement.
    var playerPolicy: PlayerPolicy {
        guard let parsed = PlayerPolicy(rawValue: policy) else {
            let known = PlayerPolicy.allCases.map(\.rawValue).joined(separator: ", ")
            print("unknown --policy '\(policy)'. Known: \(known)")
            exit(2)
        }
        return parsed
    }
}

let options = Options.parse(Array(CommandLine.arguments.dropFirst()))

// `--scale` reports the catalogue's mean forage, which is the number the
// engine's consumption constants are calibrated against.
if CommandLine.arguments.contains("--scale") {
    let all = FlowerCatalogue.all
    let nectar = all.map(\.nectarRichness).reduce(0, +) / Double(all.count)
    let pollen = all.map(\.pollenRichness).reduce(0, +) / Double(all.count)
    let sugar = all.map(\.traits.sugarYield).reduce(0, +) / Double(all.count)
    print(String(format: "mean nectarRichness %.3f", nectar))
    print(String(format: "mean pollenRichness %.3f", pollen))
    print(String(format: "mean sugarYield     %.4f", sugar))
    let locked = all.filter(\.nectarIsOutOfReach).map(\.commonName)
    print("out of reach: \(locked.joined(separator: ", "))")
    exit(0)
}

// MARK: - Setup

let start = Date(timeIntervalSince1970: 1_700_000_000)

// The real catalogue entries rather than stand-ins, so balance is measured
// against the same corolla depths, sugar concentrations and pollen protein the
// game runs on. Using approximations here once meant tuning against a forage
// model no player would ever meet.
//
// Six species rather than four, chosen to be a plausible British year rather
// than a convenient set: willow for the spring pollen, hawthorn and clover for
// the spring and summer nectar, bramble through high summer, heather on the
// moor in late summer, and ivy last of all. The old four included willow —
// which is a great pollen plant and a poor nectar one — without anything to
// balance it, so the tool was measuring a nectar-starved year and calling it
// normal.
let willow = FlowerCatalogue.willow
let hawthorn = FlowerCatalogue.hawthorn
let clover = FlowerCatalogue.whiteClover
let bramble = FlowerCatalogue.bramble
let heather = FlowerCatalogue.heather
let ivy = FlowerCatalogue.ivy

/// A spread of species, so the colony faces a realistic succession of forage
/// rather than one flower that blooms all year.
let palette = [willow, hawthorn, clover, bramble, heather, ivy]

var simulation = Simulation.newGame(
    at: HiveLocation(type: options.locationType),
    startingAt: start,
    config: options.config,
    seed: options.seed
)

if let worldSeed = options.worldSeed {
    simulation.setTerrainSeed(worldSeed)
}
if let biome = options.homeBiome {
    simulation.setTerrainBiome(biome)
}

// Top-level code is main-actor isolated under the Swift 6 language mode, and
// `simulation` is a top-level variable, so anything that mutates it has to say
// where it runs.
@MainActor
func stockPatches(_ count: Int, tag: String) {
    for index in 0..<count {
        if options.sharedForage {
            simulation.importSharedFlower(
                shareID: "\(tag)-\(index)",
                photoLocalIdentifier: "\(tag)-\(index)",
                species: palette[index % palette.count],
                confidence: 0.9,
                takenAt: start,
                sharedBy: "a friend",
                distanceMetres: options.world ? nil : options.distance
            )
        } else {
            simulation.registerPhotograph(
                photoLocalIdentifier: "\(tag)-\(index)",
                species: palette[index % palette.count],
                confidence: 0.9,
                takenAt: start,
                distanceMetres: options.world ? nil : options.distance
            )
        }
    }
}

// MARK: - Trial mode

if options.trials > 0 {
    let outcomes = Trials.run(
        trials: options.trials,
        days: options.days,
        patches: options.patches,
        distance: options.distance,
        restockEvery: options.restockEvery,
        config: options.config,
        site: options.locationType,
        palette: palette,
        start: start,
        shared: options.sharedForage,
        policy: options.playerPolicy,
        world: options.world,
        worldSeed: options.worldSeed,
        biome: options.homeBiome
    )
    print("policy: \(options.playerPolicy.rawValue)")
    if options.world {
        print("world: on"
              + (options.worldSeed.map { ", seed \($0)" } ?? ", seed per trial")
              + (options.homeBiome.map { " · \($0.rawValue) underfoot" } ?? "")
              + " · flowers planted in the garden, wild forage around it")
    }
    if CommandLine.arguments.contains("--list") { Trials.list(outcomes) }
    Trials.report(outcomes, days: options.days)
    exit(0)
}

stockPatches(options.patches, tag: "initial")

// MARK: - Report

func pad(_ text: String, _ width: Int) -> String {
    text.count >= width
        ? String(text.prefix(width))
        : text + String(repeating: " ", count: width - text.count)
}

func padLeft(_ text: String, _ width: Int) -> String {
    text.count >= width
        ? String(text.prefix(width))
        : String(repeating: " ", count: width - text.count) + text
}

/// Queen status at a glance: laying, virgin, laying workers, or gone.
func queenGlyph(_ hive: Hive) -> String {
    if hive.hasLayingQueen { return "L" }
    if hive.hasVirginQueen { return "v" }
    if hive.hasLayingWorkers { return "LW" }
    return "-"
}

func number(_ value: Double, _ decimals: Int = 0) -> String {
    String(format: "%.\(decimals)f", value)
}

let ground = options.world
    ? "\(options.patches) patches in the garden · "
        + "\(simulation.patches.filter(\.isWild).count) wild · "
        + "\(simulation.homeChunk?.name ?? "nowhere") "
        + "(\(simulation.homeChunk?.biome.rawValue ?? "-"))"
    : "\(options.patches) patches at \(number(options.distance))m"

print("""
FlowerPower colony trajectory
  preset \(options.preset) · site \(options.site) · seed \(options.seed)
  \(ground) · \(options.days) days

""")

let header = pad("day", 5) + pad("season", 8) + padLeft("pop", 5) + padLeft("adult", 6)
    + padLeft("brood", 6) + padLeft("honey", 7) + padLeft("pollen", 7) + padLeft("cells", 6)
    + padLeft("free", 5) + padLeft("eggs", 5) + padLeft("nurse", 6)
    + padLeft("temp", 6) + padLeft("mites", 7) + padLeft("vit", 6) + padLeft("Q", 4) + padLeft("qvit", 6) + padLeft("rjel", 6) + "  notes"
print(header)
print(String(repeating: "-", count: header.count + 10))

var totals = CatchUpReport()
var swarms = 0
var collapsedOn: Int?
var peakPopulation = 0
var lowestHoney = Double.infinity

for day in 0..<options.days {
    let events = simulation.stepDay()

    var notes: [String] = []
    var eggsToday = 0
    for event in events {
        totals.record(event)
        switch event {
        case .eggsLaid(let count, _):
            eggsToday += count
        case .swarmed(let lost):
            swarms += 1
            notes.append("SWARM (-\(lost))")
        case .absconded(let lost):
            notes.append("ABSCONDED (-\(lost))")
        case .queenLost: notes.append("QUEEN LOST")
        case .queenEmerged: notes.append("new queen")
        case .queenMated(let patrilines): notes.append("mated x\(patrilines)")
        case .matingFlightFailed: notes.append("MATING FAILED")
        case .supersededQueen: notes.append("superseded")
        case .layingWorkersAppeared: notes.append("LAYING WORKERS")
        case .infectionDetected(let pathogen): notes.append("+\(pathogen.rawValue)")
        case .infectionCritical(let pathogen): notes.append("!!\(pathogen.rawValue)")
        case .raidSucceeded(let predator, _): notes.append("raided by \(predator.rawValue)")
        case .colonyCollapsed:
            if collapsedOn == nil { collapsedOn = day }
            notes.append("COLLAPSED")
        case .winterStoresLow(let have, let need):
            notes.append("stores \(number(have))/\(number(need))")
        default: break
        }
    }

    peakPopulation = max(peakPopulation, simulation.hive.population)
    lowestHoney = min(lowestHoney, simulation.hive.resources[.honey])

    if options.restockEvery > 0, day % options.restockEvery == 0, day > 0 {
        simulation.pruneDepletedPatches()
        stockPatches(max(1, options.patches / 3), tag: "day\(day)")
        notes.append("restocked")
    }

    let uniqueNotes = Array(NSOrderedSet(array: notes)).compactMap { $0 as? String }
    let shouldPrint = day % options.every == 0 || !uniqueNotes.isEmpty

    if shouldPrint {
        let hive = simulation.hive
        let line = pad("\(day)", 5)
            + pad(simulation.season.rawValue, 8)
            + padLeft("\(hive.population)", 5)
            + padLeft("\(hive.adultCount)", 6)
            + padLeft("\(hive.broodCount)", 6)
            + padLeft(number(hive.resources[.honey]), 7)
            + padLeft(number(hive.resources[.pollen]), 7)
            + padLeft("\(hive.comb.builtCells)", 6)
            // Free cells and the day's eggs, which is how a honey-bound
            // colony shows itself: a laying queen, a flow on, and nothing to
            // lay into. Seed 8919 under gentle, 2026-09-24.
            + padLeft("\(hive.freeCells)", 5)
            + padLeft("\(eggsToday)", 5)
            + padLeft("\(hive.bees.filter { $0.performs(.nurseBee) }.count)", 6)
            + padLeft(number(hive.temperatureCelsius, 1), 6)
            + padLeft(number(hive.pathogens[.varroa] * 100), 6) + "%"
            + padLeft(number(hive.averageVitality, 2), 6)
            + padLeft(queenGlyph(hive), 4)
            + padLeft(number(hive.queen?.vitality ?? 0, 2), 6)
            + padLeft(number(hive.resources[.royalJelly], 1), 6)
            + "  " + uniqueNotes.prefix(3).joined(separator: ", ")
        print(line)
    }

    if simulation.hive.bees.isEmpty { break }
}

// MARK: - Summary

let hive = simulation.hive
print("")
print(String(repeating: "=", count: 60))
print("Survived:          \(hive.bees.isEmpty ? "NO" : "yes")\(collapsedOn.map { " (collapse flagged day \($0))" } ?? "")")
print("Final population:  \(hive.population)  (peak \(peakPopulation))")
print("Queenright:        \(hive.isQueenright ? (hive.queenIsMated ? "yes" : "virgin") : "NO")")
print("Comb drawn:        \(hive.comb.builtCells) / \(hive.maximumCells)")
print("Honey:             \(number(hive.resources[.honey]))  (lowest \(number(max(0, lowestHoney))))")
print("Edible energy:     \(number(hive.resources.edibleEnergy)) / \(number(hive.winterStoresRequired)) needed for winter")
print("Average vitality:  \(number(hive.averageVitality, 2))")
print("Varroa load:       \(number(hive.pathogens[.varroa] * 100, 1))%")
print("Swarms:            \(swarms)")
print("Eggs laid:         \(totals.eggsLaid)")
print("Emerged:           \(totals.totalEmerged)")
print("Died:              \(totals.totalDeaths)")
for (cause, count) in totals.died.sorted(by: { $0.value > $1.value }) {
    print("   \(pad(cause.rawValue, 16)) \(count)")
}
print("Grounded days:     \(totals.groundedDays)")
print("Stores raided:     \(number(totals.storesRaided))")
