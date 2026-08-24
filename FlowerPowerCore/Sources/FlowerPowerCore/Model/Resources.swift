//
//  Resources.swift
//  FlowerPowerCore
//

import Foundation

public enum ResourceKind: String, Codable, CaseIterable, Sendable {
    /// Gathered in the field.
    case nectar
    case pollen
    case water
    case propolis
    /// Produced inside the hive.
    case honey
    case beeBread
    case royalJelly
    case wax

    public var isForaged: Bool {
        switch self {
        case .nectar, .pollen, .water, .propolis: return true
        case .honey, .beeBread, .royalJelly, .wax: return false
        }
    }

    /// Whether this resource occupies comb cells. Water and propolis are used
    /// as they arrive rather than stored in cells, and wax *is* the comb.
    public var occupiesComb: Bool {
        switch self {
        case .nectar, .honey, .pollen, .beeBread: return true
        case .water, .propolis, .wax, .royalJelly: return false
        }
    }

    /// How much of this resource fits in one comb cell.
    public var unitsPerCell: Double {
        switch self {
        case .honey: return 4.0
        case .nectar: return 3.0      // unripened, so it takes more room
        case .beeBread: return 3.5
        case .pollen: return 3.0
        default: return .infinity
        }
    }

    /// Soft cap for resources not stored in comb, so carriers do not accumulate
    /// an unbounded lake of water.
    public var uncappedStorageLimit: Double {
        switch self {
        case .water: return 40
        case .propolis: return 60
        case .royalJelly: return 80
        case .wax: return 400
        default: return .infinity
        }
    }

    /// Royal jelly is glandular and perishes within days; honey keeps forever.
    /// Expressed as the fraction lost per day.
    public var dailySpoilage: Double {
        switch self {
        case .royalJelly: return 0.20
        case .nectar: return 0.05      // ferments if not ripened
        case .beeBread: return 0.02
        case .water: return 0.20       // evaporates
        default: return 0
        }
    }

    public var displayName: String {
        switch self {
        case .nectar: return "Nectar"
        case .pollen: return "Pollen"
        case .water: return "Water"
        case .propolis: return "Propolis"
        case .honey: return "Honey"
        case .beeBread: return "Bee Bread"
        case .royalJelly: return "Royal Jelly"
        case .wax: return "Wax"
        }
    }
}

/// Continuous quantities, so production that yields a fraction of a unit per
/// tick still accumulates instead of rounding away to nothing.
public struct ResourcePool: Codable, Equatable, Sendable {

    private var amounts: [ResourceKind: Double]

    public init(_ amounts: [ResourceKind: Double] = [:]) {
        self.amounts = amounts.filter { $0.value > 0 }
    }

    public subscript(kind: ResourceKind) -> Double {
        get { amounts[kind] ?? 0 }
        set {
            let clamped = max(0, newValue)
            if clamped <= 1e-9 {
                amounts.removeValue(forKey: kind)
            } else {
                amounts[kind] = clamped
            }
        }
    }

    /// Adds up to `limit`, returning the amount that would not fit. Callers
    /// that ignore the overflow are choosing to let it spill.
    @discardableResult
    public mutating func add(
        _ amount: Double,
        of kind: ResourceKind,
        limit: Double = .infinity
    ) -> Double {
        guard amount > 0 else { return 0 }
        let space = max(0, limit - self[kind])
        let accepted = min(amount, space)
        self[kind] += accepted
        return amount - accepted
    }

    /// Consumes up to `amount` and reports what was actually available.
    @discardableResult
    public mutating func drain(_ amount: Double, of kind: ResourceKind) -> Double {
        let taken = min(max(0, amount), self[kind])
        self[kind] -= taken
        return taken
    }

    /// All-or-nothing consumption, for recipes that must not part-complete.
    @discardableResult
    public mutating func consume(_ amount: Double, of kind: ResourceKind) -> Bool {
        guard self[kind] >= amount else { return false }
        self[kind] -= amount
        return true
    }

    /// Comb cells currently occupied by stored resources.
    public var cellsOccupied: Int {
        var cells = 0.0
        for (kind, amount) in amounts where kind.occupiesComb {
            cells += amount / kind.unitsPerCell
        }
        return Int(cells.rounded(.up))
    }

    public var isEmpty: Bool { amounts.isEmpty }
    public var stored: [ResourceKind: Double] { amounts }

    /// Honey equivalent of everything edible in the hive — the number that
    /// actually decides whether the colony survives the winter.
    public var edibleEnergy: Double {
        self[.honey] + self[.nectar] / 3.0 + self[.beeBread] * 0.6 + self[.royalJelly] * 0.5
    }
}
