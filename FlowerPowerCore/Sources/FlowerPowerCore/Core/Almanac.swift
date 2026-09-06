//
//  Almanac.swift
//  FlowerPowerCore
//
//  The colony's year, written by the game.
//
//  One line a day at most, and only when something happened. The first flow,
//  the first swarm cell, the day the honey peaked, a raid, a queen coming home
//  mated, what ended it all. Nothing routine: births and deaths happen every
//  day and are not news.
//
//  This is what winter is for. There is nothing to photograph and little to
//  watch, and a colony that has been through a year has a year to read.
//

import Foundation

public struct AlmanacEntry: Codable, Equatable, Identifiable, Sendable {

    public enum Kind: String, Codable, Sendable {
        case season, forage, queen, swarm, threat, disease, stores, harvest, colony
    }

    public let day: Int
    public let season: Season
    public let kind: Kind
    public let text: String

    public init(day: Int, season: Season, kind: Kind, text: String) {
        self.day = day
        self.season = season
        self.kind = kind
        self.text = text
    }

    public var id: String { "\(day)-\(kind.rawValue)-\(text.hashValue)" }
    public var year: Int { day / Season.daysPerYear + 1 }
    public var dayOfYear: Int { day % Season.daysPerYear + 1 }
}

public struct Almanac: Codable, Equatable, Sendable {

    public private(set) var entries: [AlmanacEntry]

    /// Enough for a couple of years of a busy colony. Older lines go.
    public static let limit = 400

    /// Honey high-water mark, so "the honey peaked" is written once when it is
    /// true rather than every day it climbs.
    public private(set) var peakHoney: Double

    public init(entries: [AlmanacEntry] = [], peakHoney: Double = 0) {
        self.entries = entries
        self.peakHoney = peakHoney
    }

    public var isEmpty: Bool { entries.isEmpty }

    public func entries(inYear year: Int) -> [AlmanacEntry] {
        entries.filter { $0.year == year }
    }

    public var latestYear: Int { entries.last?.year ?? 1 }

    // MARK: - Writing

    mutating func write(_ kind: AlmanacEntry.Kind, _ text: String, day: Int) {
        let season = Season(day: day)
        // One line per kind per day. A wasp siege produces several attack
        // events across the day; the almanac says it once.
        if entries.last(where: { $0.day == day && $0.kind == kind && $0.text == text }) != nil {
            return
        }
        entries.append(AlmanacEntry(day: day, season: season, kind: kind, text: text))
        if entries.count > Self.limit {
            entries.removeFirst(entries.count - Self.limit)
        }
    }

    /// Turns a day's events into lines. Called once per tick with that tick's
    /// events; the per-kind dedupe above makes that safe.
    public mutating func chronicle(
        _ events: [SimEvent],
        day: Int,
        honey: Double,
        lineage: Lineage
    ) {
        // Season turning is not an event, it is a date. Written on the first
        // day of each season.
        if day % Season.daysPerSeason == 0 {
            let season = Season(day: day)
            write(.season, "\(season.rawValue.capitalized) begins.", day: day)
        }

        // The honey peak is worth exactly one line, on the day it is set.
        if honey > peakHoney {
            let wasMeaningful = peakHoney > 0 && honey > peakHoney * 1.05
            peakHoney = honey
            if wasMeaningful, Season(day: day) != .winter {
                write(.stores, "Stores reach a new high of \(Int(honey.rounded())) units.", day: day)
            }
        }

        let queen = lineage.reigning?.title ?? "The queen"

        for event in events {
            switch event {
            case .nectarFlowBegan:
                write(.forage, "The nectar begins to flow.", day: day)
            case .dearth:
                write(.forage, "A dearth. Little is coming in.", day: day)
            case .queenCellStarted(let purpose):
                switch purpose {
                case .swarm: write(.swarm, "The first swarm cells are started.", day: day)
                case .supersedure: write(.queen, "The bees begin raising a successor to \(queen).", day: day)
                case .emergency: write(.queen, "Queenless, the colony raises an emergency queen.", day: day)
                }
            case .queenEmerged:
                write(.queen, "A new queen emerges.", day: day)
            case .queenMated(let patrilines):
                write(.queen, "\(queen) returns from her mating flight, mated with \(patrilines) drones.", day: day)
            case .matingFlightFailed:
                write(.queen, "The virgin queen does not return from her mating flight.", day: day)
            case .queenLost:
                write(.queen, "\(queen) is lost.", day: day)
            case .supersededQueen:
                write(.queen, "\(queen) is superseded.", day: day)
            case .swarmed(let lost):
                write(.swarm, "A swarm leaves with \(lost) bees and the old queen.", day: day)
            case .swarmPreparing(let departs):
                write(.swarm, "Swarm cells are capped; the colony will divide in about \(max(1, departs - day)) days.", day: day)
            case .swarmAbandoned:
                write(.swarm, "The swarm is called off. The bees tear down their queen cells.", day: day)
            case .combAdded(let cells):
                write(.colony, "The nest is opened up: room for \(cells) more cells.", day: day)
            case .colonyDivided(let left):
                write(.swarm, "The colony is divided on purpose. \(left) bees leave with \(queen); "
                      + "the flying bees stay.", day: day)
            case .absconded(let lost):
                write(.colony, "The colony absconds, \(lost) bees abandoning the nest.", day: day)
            case .layingWorkersAppeared:
                write(.queen, "Laying workers appear. There is no way back from this.", day: day)
            case .colonyCollapsed:
                write(.colony, "The colony is gone.", day: day)
            case .threatBegan(let predator, _):
                write(.threat, "\(predator.displayName) at the nest.", day: day)
            case .attackRepelled(let predator):
                write(.threat, "The \(predator.displayName.lowercased()) is driven off.", day: day)
            case .raidSucceeded(let predator, let stores):
                write(.threat, "\(predator.displayName) get in and take \(Int(stores.rounded())) units of stores.", day: day)
            case .combLost(let count):
                write(.threat, "\(count) cells of comb are destroyed.", day: day)
            case .infectionDetected(let pathogen):
                write(.disease, "\(pathogen.displayName) is found in the colony.", day: day)
            case .infectionCritical(let pathogen):
                write(.disease, "\(pathogen.displayName) reaches a dangerous level.", day: day)
            case .infectionCleared(let pathogen):
                write(.disease, "The colony clears \(pathogen.displayName.lowercased()).", day: day)
            case .winterStoresLow(let have, let need):
                write(.stores, "Winter stores are short: \(Int(have)) of \(Int(need)) needed.", day: day)
            case .entranceSealed(let sealed):
                write(.colony, sealed
                      ? "The bees seal the entrance with propolis for winter."
                      : "The entrance is left open through the winter.", day: day)
            case .honeyTaken(let units):
                write(.harvest, "\(Int(units.rounded())) units of honey are taken.", day: day)
            case .postureAdopted(let posture):
                if posture != .instinct {
                    write(.colony, "\(posture.displayName).", day: day)
                }
            default:
                break
            }
        }
    }
}
