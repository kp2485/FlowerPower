//
//  SwarmShare.swift
//  FlowerPowerGame
//
//  A swarm, packaged up to give to somebody.
//
//  When a colony swarms, the old queen leaves with sixty per cent of the bees
//  and no home. Catching that swarm is how most beekeepers get their second
//  colony, and giving it to a friend is the same thing at one remove: they
//  receive a file, and on opening it may start a colony from it at a site
//  they choose — the queen with her number, the bees, and the honey in their
//  crops. Nothing else, which is the starting position every real swarm has.
//
//  Built on the same principles as `FlowerShare`: a self-contained file
//  through the share sheet, no server, everything received clamped rather
//  than trusted. A swarm is a bigger gift than a flower, so the caps are
//  tighter — a swarm of ten thousand bees would be a colony that never
//  existed.
//

import Foundation
import FlowerPowerCore

public struct SwarmShare: Codable, Equatable, Sendable, Identifiable {

    public static let currentVersion = 1
    public static let fileExtension = "swarm"
    public static let contentType = "com.kylepeterson.flowerpower.swarm"

    /// A prime swarm from a strong colony is a few hundred bees in this
    /// model's scale. Anything past this is not a swarm.
    public static let maximumWorkers = 600

    public var version: Int
    public var id: String
    /// The queen who left, with her number and name if she had one.
    public var queen: QueenRecord?
    public var workerCount: Int
    public var genetics: QueenGenetics
    public var honeyCarried: Double
    public var sharedBy: String?
    public var note: String?

    public init(
        version: Int = SwarmShare.currentVersion,
        id: String = UUID().uuidString,
        queen: QueenRecord?,
        workerCount: Int,
        genetics: QueenGenetics,
        honeyCarried: Double,
        sharedBy: String?,
        note: String? = nil
    ) {
        self.version = version
        self.id = id
        self.queen = queen
        self.workerCount = workerCount
        self.genetics = genetics
        self.honeyCarried = honeyCarried
        self.sharedBy = sharedBy
        self.note = note
    }

    /// Packages the swarm that just left a colony.
    public init(
        _ swarm: DepartedSwarm,
        lineage: Lineage,
        sharedBy: String?,
        note: String? = nil
    ) {
        self.init(
            queen: swarm.queenNumber.flatMap { number in
                lineage.queens.first { $0.number == number }
            },
            workerCount: swarm.workers.count,
            genetics: swarm.genetics,
            honeyCarried: swarm.honeyCarried,
            sharedBy: sharedBy,
            note: note
        )
    }

    public var queenTitle: String { queen?.title ?? "A swarm queen" }

    // MARK: - Back into bees

    /// Rebuilds a swarm the engine can found a colony from.
    ///
    /// The bees themselves do not travel — only their number — so they are
    /// made afresh: adult workers spread across flying ages, and a mated
    /// queen. Identifiers are placeholders; `Simulation.newGame(fromSwarm:)`
    /// issues real ones from the new colony's generator.
    public func departedSwarm() -> DepartedSwarm {
        let queen = Bee(
            id: .unassigned, kind: .queen, stage: .adult,
            daysInStage: 40, vitality: max(0.5, self.queen?.quality ?? 1)
        )
        let workers = (0..<workerCount).map { index in
            Bee(
                id: .unassigned, kind: .worker, stage: .adult,
                // Foragers go with a swarm, so these are flying-age bees.
                daysInStage: 18 + (index * 17) / max(1, workerCount),
                patriline: UInt8(index % max(1, genetics.patrilines))
            )
        }
        return DepartedSwarm(
            day: 0,
            queen: queen,
            workers: workers,
            genetics: genetics,
            honeyCarried: honeyCarried,
            queenNumber: self.queen?.number
        )
    }

    // MARK: - Reading and writing

    public enum Failure: Error, LocalizedError, Equatable {
        case notASwarmFile
        case fromANewerVersion(Int)
        case noBees

        public var errorDescription: String? {
            switch self {
            case .notASwarmFile: return "That does not look like a swarm someone sent."
            case .fromANewerVersion:
                return "This swarm came from a newer version of FlowerPower. Update to open it."
            case .noBees: return "That swarm arrived with no bees in it."
            }
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> SwarmShare {
        guard data.count < 64 * 1024 else { throw Failure.notASwarmFile }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let share: SwarmShare
        do {
            share = try decoder.decode(SwarmShare.self, from: data)
        } catch {
            throw Failure.notASwarmFile
        }

        guard share.version <= currentVersion else {
            throw Failure.fromANewerVersion(share.version)
        }
        guard share.workerCount > 0 else { throw Failure.noBees }

        return share.validated()
    }

    /// Everything clamped into a range the engine can found a colony from.
    public func validated() -> SwarmShare {
        var copy = self
        copy.workerCount = min(Self.maximumWorkers, max(1, workerCount))
        copy.honeyCarried = honeyCarried.isFinite
            ? min(Double(copy.workerCount) * 0.5, max(0, honeyCarried))
            : 0
        copy.genetics = QueenGenetics(
            patrilines: min(30, max(1, genetics.patrilines)),
            hygienicBehaviour: clamp(genetics.hygienicBehaviour),
            defensiveness: clamp(genetics.defensiveness),
            fecundity: min(1.5, max(0.5, genetics.fecundity.isFinite ? genetics.fecundity : 1)),
            swarminess: clamp(genetics.swarminess),
            thriftiness: clamp(genetics.thriftiness)
        )
        copy.sharedBy = sharedBy.flatMap(Self.tidy)
        copy.note = note.flatMap(Self.tidy)
        if let queen = queen {
            var clean = queen
            clean.name = queen.name.flatMap(Self.tidy)
            copy.queen = clean
        }
        if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copy.id = UUID().uuidString
        }
        return copy
    }

    private func clamp(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0.5
    }

    private static func tidy(_ text: String) -> String? {
        let clean = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(80)
        return clean.isEmpty ? nil : String(clean)
    }
}
