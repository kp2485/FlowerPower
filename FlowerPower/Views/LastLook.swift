//
//  LastLook.swift
//  FlowerPower
//
//  What the colony looked like when the player last put the phone down.
//
//  Coming back after an hour, the numbers have moved and nothing says by how
//  much. A full-screen report for every short absence was the only answer the
//  game had, and it was too big an answer for "eighty more bees and a little
//  less honey". So the dashboard keeps the last look, and each figure says
//  how far it has come since — and the report sheet is kept for an absence
//  that actually has a story in it.
//

import SwiftUI
import FlowerPowerCore

struct LastLook: Codable, Equatable {

    var resources: [String: Double]
    var total: Int
    var adults: Int
    var brood: Int
    var drones: Int
    var takenAt: Date

    init(_ snapshot: ColonySnapshot, at date: Date = Date()) {
        resources = Dictionary(
            uniqueKeysWithValues: snapshot.stores.resources.map { ($0.key.rawValue, $0.value) }
        )
        total = snapshot.population.total
        adults = snapshot.population.adults
        brood = snapshot.population.brood
        drones = snapshot.population.drones
        takenAt = date
    }

    func resource(_ kind: ResourceKind) -> Double { resources[kind.rawValue] ?? 0 }

    // MARK: Keeping it

    private static let key = "lastLook"

    /// Under this long away and the differences are the live tick's, which the
    /// rolling digits already show.
    static let worthShowingAfter: TimeInterval = 10 * 60

    static func record(_ snapshot: ColonySnapshot) {
        if let data = try? JSONEncoder().encode(LastLook(snapshot)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// For a colony that is not the one that was last looked at.
    static func forget() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func stored() -> LastLook? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LastLook.self, from: data)
    }
}

extension EnvironmentValues {
    /// The last look, when it is old enough to be worth comparing against.
    @Entry var lastLook: LastLook?
}

/// The chip's change, said aloud. A tile's own label replaces whatever is
/// inside it, so the chip's label was never reached.
func spoken(delta: Double?) -> String {
    guard let delta else { return "" }
    let rounded = Int(delta.rounded())
    guard rounded != 0 else { return "" }
    return rounded > 0
        ? ", up \(rounded) since you last looked"
        : ", down \(abs(rounded)) since you last looked"
}

/// "+120" or "−8", small, under a figure.
struct DeltaChip: View {

    let delta: Double

    private var rounded: Int { Int(delta.rounded()) }

    var body: some View {
        if rounded != 0 {
            Text(rounded > 0 ? "+\(rounded)" : "\u{2212}\(abs(rounded))")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(rounded > 0 ? Theme.healthy : Theme.caution)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    (rounded > 0 ? Theme.healthy : Theme.caution).opacity(0.15),
                    in: Capsule()
                )
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(rounded > 0 ? "up \(rounded) since you last looked" : "down \(abs(rounded)) since you last looked")
        }
    }
}

extension CatchUpReport {

    /// Whether this absence has a story worth a sheet of its own.
    ///
    /// A few quiet simulated days are told by the dashboard's "since you last
    /// looked" figures instead. Anything the player would want to hear about
    /// in so many words — a swarm, the queen, a raid, a sickness, a badge —
    /// still gets the sheet, however short the absence.
    var deservesASheet: Bool {
        daysSimulated >= 3
            || swarmed || absconded || queenLost || queenMated || superseded
            || layingWorkers || collapsed || starved
            || !attacks.isEmpty || !milestones.isEmpty
            || !newInfections.isEmpty || !criticalInfections.isEmpty
    }
}
