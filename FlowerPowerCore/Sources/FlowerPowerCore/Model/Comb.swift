//
//  Comb.swift
//  FlowerPowerCore
//
//  Comb is simultaneously the colony's nursery and its pantry, and the two
//  compete for the same cells. That competition is the central tension of a
//  real hive: a colony that fills every cell with honey has nowhere to raise
//  the bees that will collect next year's honey, so it swarms.
//

import Foundation

public enum CellType: String, Codable, CaseIterable, Sendable {
    case worker
    case drone
    case queenCup

    public var displayName: String {
        switch self {
        case .worker: return "Worker Cell"
        case .drone: return "Drone Cell"
        case .queenCup: return "Queen Cup"
        }
    }

    /// Wax required to draw one cell. Drone cells are noticeably larger, and a
    /// queen cell is a substantial construction.
    ///
    /// Scaled so that drawing out a full nest costs a few hundred honey — a
    /// real but affordable share of a season's surplus, at the file-level
    /// honey-to-wax ratio of seven to one.
    public var waxCost: Double {
        switch self {
        case .worker: return 0.08
        case .drone: return 0.11
        case .queenCup: return 0.40
        }
    }
}

/// A developing queen. Colonies raise these for three quite different reasons,
/// and the reason determines what happens when she emerges.
public struct QueenCell: Identifiable, Codable, Equatable, Sendable {

    public enum Purpose: String, Codable, Sendable {
        /// The colony is preparing to swarm; the old queen leaves with half the bees.
        case swarm
        /// The queen is failing and is being quietly replaced.
        case supersedure
        /// The queen is already gone; this is a last-ditch attempt from young brood.
        case emergency

        public var displayName: String {
            switch self {
            case .swarm: return "Swarm Cell"
            case .supersedure: return "Supersedure Cell"
            case .emergency: return "Emergency Cell"
            }
        }
    }

    public let id: EntityID
    public let purpose: Purpose
    public private(set) var daysDeveloped: Int

    /// Emergency queens are reared from larvae already too old for the job, and
    /// emerge correspondingly poorer.
    public let quality: Double

    public init(id: EntityID, purpose: Purpose, quality: Double = 1.0) {
        self.id = id
        self.purpose = purpose
        self.daysDeveloped = 0
        self.quality = min(1, max(0, quality))
    }

    /// A queen takes 16 days from egg, but a cell is usually started on a
    /// larva already a few days old.
    public static let daysToEmergence = 12

    public var isReady: Bool { daysDeveloped >= Self.daysToEmergence }

    public mutating func advanceOneDay() {
        daysDeveloped += 1
    }
}

public struct Comb: Codable, Equatable, Sendable {

    /// Cells drawn, by type.
    public private(set) var cells: [CellType: Int]

    /// Queen cells under construction or capped.
    public var queenCells: [QueenCell]

    /// Hard ceiling imposed by the cavity.
    /// The cavity, in cells. Not fixed for the life of the nest: `extend`
    /// raises it when the colony is given more room. See
    /// `HiveLocationType.extensionRoom` for where that room comes from.
    public private(set) var capacity: Int

    public init(
        workerCells: Int = 60,
        droneCells: Int = 0,
        capacity: Int = 700
    ) {
        self.cells = [.worker: max(0, workerCells), .drone: max(0, droneCells)]
        self.queenCells = []
        self.capacity = max(1, capacity)
    }

    public subscript(type: CellType) -> Int {
        cells[type] ?? 0
    }

    public var builtCells: Int {
        (cells[.worker] ?? 0) + (cells[.drone] ?? 0)
    }

    public var freeCapacity: Int { max(0, capacity - builtCells) }

    /// Gives the nest more room to draw into. Returns the cells actually
    /// added, which is zero for a non-positive request.
    ///
    /// Only the space changes. Comb still has to be drawn into it, at seven
    /// units of honey to one of wax and only during a flow — so this is an
    /// opportunity, not an endowment.
    @discardableResult
    public mutating func extend(by cells: Int) -> Int {
        guard cells > 0 else { return 0 }
        capacity += cells
        return cells
    }

    public var canExpand: Bool { builtCells < capacity }

    /// Drone comb should be roughly a tenth to a sixth of the nest. Colonies
    /// with too little of it will chew worker comb into drone comb — and, in a
    /// managed hive, that drone brood is where varroa breeds fastest.
    public static let targetDroneShare: Double = 0.14

    public var droneShare: Double {
        guard builtCells > 0 else { return 0 }
        return Double(cells[.drone] ?? 0) / Double(builtCells)
    }

    public var needsDroneComb: Bool { droneShare < Self.targetDroneShare }

    @discardableResult
    public mutating func build(_ count: Int, as type: CellType) -> Int {
        guard count > 0, type != .queenCup else { return 0 }
        let actual = min(count, freeCapacity)
        guard actual > 0 else { return 0 }
        cells[type, default: 0] += actual
        return actual
    }

    /// Wax moths and neglect destroy comb. A colony too small to patrol its own
    /// nest loses it.
    @discardableResult
    public mutating func destroy(_ count: Int, of type: CellType) -> Int {
        let available = cells[type] ?? 0
        let actual = min(max(0, count), available)
        cells[type] = available - actual
        return actual
    }

    /// The bees tear down cells of one purpose — a swarm called off.
    public mutating func removeQueenCells(ofPurpose purpose: QueenCell.Purpose) {
        queenCells.removeAll { $0.purpose == purpose }
    }

    public mutating func addQueenCell(_ cell: QueenCell) {
        queenCells.append(cell)
    }

    /// The colony tears down rival queen cells once one has won.
    public mutating func tearDownQueenCells(except survivor: EntityID? = nil) {
        queenCells.removeAll { $0.id != survivor }
    }

    public var hasQueenCells: Bool { !queenCells.isEmpty }
    public var readyQueenCells: [QueenCell] { queenCells.filter(\.isReady) }
}
