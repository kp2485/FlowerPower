//
//  Lineage.swift
//  FlowerPowerCore
//
//  Who reigned, for how long, and how it ended.
//
//  The simulation has always produced this — swarms, supersedures, mating
//  flights that did and did not come back — and then thrown it away. An idle
//  game lives on legacy, and this is the legacy a colony actually has: not a
//  score, but a line of queens.
//
//  Queens are numbered in Roman numerals because that is how a beekeeper who
//  cared would do it, and because "Queen IV, daughter of Queen II" reads as a
//  dynasty in a way "queen 4" does not. Names are the player's to give.
//

import Foundation

public struct QueenRecord: Codable, Equatable, Identifiable, Sendable {

    public enum Ending: String, Codable, Sendable {
        case oldAge
        case predation
        case superseded
        case leftWithSwarm
        case lost
        case matingFailed
        case colonyEnded

        public var displayName: String {
            switch self {
            case .oldAge: return "Died of old age"
            case .predation: return "Killed by a predator"
            case .superseded: return "Superseded by her daughter"
            case .leftWithSwarm: return "Left with a swarm"
            case .lost: return "Lost"
            case .matingFailed: return "Never returned from her mating flight"
            case .colonyEnded: return "Outlived her colony"
            }
        }
    }

    public let number: Int
    public var name: String?
    /// The queen whose egg she was raised from, when it is known.
    public let motherNumber: Int?
    public let emergedOnDay: Int
    public var matedOnDay: Int?
    public var patrilines: Int?
    /// Quality at emergence, 0...1 — a well-fed cell makes a better queen.
    public let quality: Double
    public var endedOnDay: Int?
    public var ending: Ending?

    public init(
        number: Int,
        name: String? = nil,
        motherNumber: Int?,
        emergedOnDay: Int,
        matedOnDay: Int? = nil,
        patrilines: Int? = nil,
        quality: Double = 1,
        endedOnDay: Int? = nil,
        ending: Ending? = nil
    ) {
        self.number = number
        self.name = name
        self.motherNumber = motherNumber
        self.emergedOnDay = emergedOnDay
        self.matedOnDay = matedOnDay
        self.patrilines = patrilines
        self.quality = quality
        self.endedOnDay = endedOnDay
        self.ending = ending
    }

    public var id: Int { number }
    public var isReigning: Bool { endedOnDay == nil }

    /// "Queen IV", or the name she was given.
    public var title: String {
        name ?? "Queen \(Self.roman(number))"
    }

    public func reignDays(on today: Int) -> Int {
        (endedOnDay ?? today) - emergedOnDay
    }

    /// Roman numerals, because a dynasty deserves them.
    public static func roman(_ value: Int) -> String {
        guard value > 0 else { return "0" }
        let table: [(Int, String)] = [
            (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
            (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
            (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")
        ]
        var remaining = value
        var result = ""
        for (amount, numeral) in table {
            while remaining >= amount {
                result += numeral
                remaining -= amount
            }
        }
        return result
    }
}

// MARK: - The line

public struct Lineage: Codable, Equatable, Sendable {

    public private(set) var queens: [QueenRecord]
    /// Which colony this is, counting from the first the player founded.
    public var generation: Int

    public init(queens: [QueenRecord] = [], generation: Int = 1) {
        self.queens = queens
        self.generation = generation
    }

    public var reigning: QueenRecord? { queens.last { $0.isReigning } }
    public var count: Int { queens.count }
    private var nextNumber: Int { (queens.map(\.number).max() ?? 0) + 1 }

    /// A new queen has emerged. Her mother is whoever was reigning, or the
    /// most recent queen if the colony was queenless when she was raised.
    @discardableResult
    public mutating func crown(onDay day: Int, quality: Double) -> QueenRecord {
        let mother = reigning?.number ?? queens.last?.number
        let record = QueenRecord(
            number: nextNumber,
            motherNumber: mother,
            emergedOnDay: day,
            quality: quality
        )
        queens.append(record)
        return record
    }

    /// The founding queen, who arrived with the swarm already mated.
    public mutating func found(onDay day: Int, patrilines: Int) {
        guard queens.isEmpty else { return }
        var record = QueenRecord(number: 1, motherNumber: nil, emergedOnDay: day)
        record.matedOnDay = day
        record.patrilines = patrilines
        queens.append(record)
    }

    public mutating func mated(onDay day: Int, patrilines: Int) {
        guard let index = queens.lastIndex(where: \.isReigning) else { return }
        queens[index].matedOnDay = day
        queens[index].patrilines = patrilines
    }

    public mutating func end(onDay day: Int, _ ending: QueenRecord.Ending) {
        guard let index = queens.lastIndex(where: \.isReigning) else { return }
        queens[index].endedOnDay = day
        queens[index].ending = ending
    }

    /// Ends a specific queen rather than whoever reigns, for the moment a
    /// mother and her successor are both alive.
    public mutating func endQueen(number: Int, onDay day: Int, _ ending: QueenRecord.Ending) {
        guard let index = queens.firstIndex(where: { $0.number == number && $0.isReigning })
        else { return }
        queens[index].endedOnDay = day
        queens[index].ending = ending
    }

    public mutating func name(_ number: Int, _ name: String?) {
        guard let index = queens.firstIndex(where: { $0.number == number }) else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        queens[index].name = (trimmed?.isEmpty ?? true) ? nil : String(trimmed!.prefix(40))
    }

    /// A queen who went with a swarm carries her record into the new colony.
    public static func continuing(from record: QueenRecord?, generation: Int) -> Lineage {
        guard var carried = record else { return Lineage(generation: generation) }
        carried.endedOnDay = nil
        carried.ending = nil
        return Lineage(queens: [carried], generation: generation)
    }
}
