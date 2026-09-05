//
//  Pathology.swift
//  FlowerPowerCore
//
//  Varroa destructor is the reason most managed colonies die. The mite breeds
//  in sealed brood, feeds on the developing pupa, and vectors deformed wing
//  virus. A colony rarely dies of mites directly — it dies of the viruses the
//  mites carry, usually in its second autumn, which is why the collapse always
//  looks sudden.
//

import Foundation

public enum Pathogen: String, Codable, CaseIterable, Sendable {
    case varroa
    case deformedWingVirus
    case nosema
    case chalkbrood
    case americanFoulbrood

    public var displayName: String {
        switch self {
        case .varroa: return "Varroa Mites"
        case .deformedWingVirus: return "Deformed Wing Virus"
        case .nosema: return "Nosema"
        case .chalkbrood: return "Chalkbrood"
        case .americanFoulbrood: return "American Foulbrood"
        }
    }

    /// Whether hygienic workers can meaningfully clear this by uncapping and
    /// removing affected brood.
    /// How much of the infection hygienic workers can actually reach.
    ///
    /// Uncapping only exposes what is inside the cell. For a brood disease that
    /// is the entire reservoir, and hauling the larva out removes it. Varroa is
    /// the exception that matters: at any moment roughly half the mites are
    /// phoretic, riding adult bees, where no amount of uncapping touches them —
    /// and a mite whose cell is opened frequently just walks out and re-infests.
    /// That is why hygienic stock slows varroa without ever clearing it, and
    /// why untreated colonies still die of it.
    ///
    /// Treating varroa as fully exposed made hygienic removal outrun mite
    /// growth roughly fourfold, so varroa arrived at its seed level and was
    /// gone days later. Twenty-four test colonies recorded zero disease deaths.
    public var hygieneSusceptibility: Double {
        switch self {
        case .chalkbrood, .americanFoulbrood: return 1.0
        // Reachable only in the small share of mites that are both inside a
        // capped cell right now and in a cell the bees actually detect. Both
        // fractions are well under half, and their product is what matters —
        // which is why hygienic stock slows varroa by a useful margin rather
        // than the order of magnitude a naive reading suggests.
        case .varroa: return 0.05
        // The virus is in the bees themselves, not just the brood.
        case .deformedWingVirus: return 0.35
        case .nosema: return 0
        }
    }

    public var respondsToHygiene: Bool { hygieneSusceptibility > 0 }

    /// How far the colony's heritable resistance slows this infection, as a
    /// coefficient on `Genetics.diseaseResistance`.
    ///
    /// Per-pathogen because a single figure double-counted hygienic behaviour
    /// against varroa: `diseaseResistance` is 40% hygiene, so hygiene both
    /// suppressed mite reproduction *and* removed mites, and the two together
    /// outran growth. Against varroa what genetics really buys is grooming,
    /// which is real but modest — the strong heritable defence is VSH, and that
    /// is already modelled as hygienic removal.
    public var geneticSuppression: Double {
        switch self {
        case .varroa: return 0.20              // grooming only
        case .deformedWingVirus: return 0.50
        case .nosema: return 0.60
        case .chalkbrood: return 0.70
        case .americanFoulbrood: return 0.50
        }
    }

    /// Daily growth rate of the infection when unchecked.
    public var baseGrowthRate: Double {
        switch self {
        case .varroa: return 0.021          // mite populations roughly double monthly
        case .deformedWingVirus: return 0.05
        case .nosema: return 0.03
        case .chalkbrood: return 0.04
        case .americanFoulbrood: return 0.06
        }
    }

    /// How lethal a fully established infection is to the brood each day.
    public var broodLethality: Double {
        switch self {
        case .varroa: return 0.010
        case .deformedWingVirus: return 0.020
        case .nosema: return 0.004
        case .chalkbrood: return 0.012
        case .americanFoulbrood: return 0.045
        }
    }

    /// How lethal it is to adults each day.
    public var adultLethality: Double {
        switch self {
        case .varroa: return 0.002
        case .deformedWingVirus: return 0.014
        case .nosema: return 0.011
        case .chalkbrood: return 0.001
        case .americanFoulbrood: return 0.010
        }
    }
}

/// Infection levels, each 0...1, where 1 is a fully overwhelmed colony.
public struct PathogenLoad: Codable, Equatable, Sendable {

    private var levels: [Pathogen: Double]

    public init(_ levels: [Pathogen: Double] = [:]) {
        self.levels = levels.filter { $0.value > 0 }
    }

    public subscript(pathogen: Pathogen) -> Double {
        get { levels[pathogen] ?? 0 }
        set {
            let clamped = min(1.0, max(0.0, newValue))
            if clamped <= 0.0001 {
                levels.removeValue(forKey: pathogen)
            } else {
                levels[pathogen] = clamped
            }
        }
    }

    public var active: [Pathogen: Double] { levels }
    public var isHealthy: Bool { levels.isEmpty }

    /// The worst single infection, which is what the UI should surface.
    public var dominant: (pathogen: Pathogen, level: Double)? {
        levels.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }

    /// Combined pressure, saturating rather than summing past 1 so a colony
    /// with three mild problems is not treated as worse than dead.
    public var totalPressure: Double {
        // Probabilistic union: 1 - product of survivals.
        1 - levels.values.reduce(1.0) { $0 * (1 - $1) }
    }

    /// Deformed wing virus rides on varroa. Above roughly a 3% mite load — 0.3
    /// here — the virus takes off, and that is what actually kills the colony.
    public static let varroaVirusThreshold: Double = 0.3
}
