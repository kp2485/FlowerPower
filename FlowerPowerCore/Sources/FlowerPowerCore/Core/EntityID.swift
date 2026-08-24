//
//  EntityID.swift
//  FlowerPowerCore
//

/// Identity for anything the simulation creates.
///
/// Deliberately *not* `UUID`: `UUID()` draws on system randomness, which makes
/// the simulation irreproducible. Two runs from the same seed would diverge the
/// moment a bee was born, so offline catch-up could not be trusted to match
/// live play. Ids are drawn from a counter that is itself part of saved state.
public struct EntityID: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {

    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: EntityID, rhs: EntityID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String { "#\(rawValue)" }

    /// Placeholder for entities that have not been admitted to the world yet.
    public static let unassigned = EntityID(rawValue: 0)
}

/// Monotonic, save-safe source of `EntityID`s.
public struct IDGenerator: Codable, Equatable, Sendable {

    private var nextValue: UInt64

    public init(startingAt value: UInt64 = 1) {
        self.nextValue = value
    }

    public mutating func next() -> EntityID {
        defer { nextValue += 1 }
        return EntityID(rawValue: nextValue)
    }
}
