//
//  BloomPrompt.swift
//  FlowerPowerGame
//
//  What is out there to photograph this month.
//
//  The simulation keeps its own calendar — a colony founded in September
//  starts in simulated spring — but a player going for a walk is in the real
//  one. This works from the real date and the hemisphere, and from nothing
//  more: not the player's location, which the game does not need and does not
//  ask for beyond what a photograph already carries.
//

import Foundation
import FlowerPowerCore

public enum Hemisphere: String, Codable, Sendable {
    case northern
    case southern

    public static func containing(latitude: Double) -> Hemisphere {
        latitude < 0 ? .southern : .northern
    }
}

public enum RealSeason {

    /// Meteorological seasons, which are the ones flowers keep: spring is
    /// March to May in the north, September to November in the south.
    public static func current(
        on date: Date = Date(),
        in hemisphere: Hemisphere = .northern,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Season {
        let month = calendar.component(.month, from: date)
        let northern: Season
        switch month {
        case 3...5: northern = .spring
        case 6...8: northern = .summer
        case 9...11: northern = .autumn
        default: northern = .winter
        }

        guard hemisphere == .southern else { return northern }
        switch northern {
        case .spring: return .autumn
        case .summer: return .winter
        case .autumn: return .spring
        case .winter: return .summer
        }
    }
}

public struct BloomPrompt: Equatable, Sendable {

    public let season: Season
    /// Everything in the catalogue that flowers now.
    public let inBloom: [FlowerSpecies]
    /// The ones the player has not yet photographed, best forage first.
    public let notYetPhotographed: [FlowerSpecies]
    /// Families flowering now that the garden has no member of.
    public let missingFamilies: [PlantFamily]
    /// Plants that flower when little else does. Worth pointing out.
    public let keystones: [FlowerSpecies]

    public init(
        date: Date = Date(),
        hemisphere: Hemisphere = .northern,
        patches: [PatchSummary]
    ) {
        let season = RealSeason.current(on: date, in: hemisphere)
        let collection = BotanyCollection(patches: patches)

        let flowering = FlowerCatalogue.inBloom(during: season)
        self.season = season
        self.inBloom = flowering
        self.notYetPhotographed = flowering.filter { !collection.speciesCollected.contains($0.id) }
        self.keystones = flowering.filter(\.isKeystone)

        let familiesFlowering = Set(flowering.map(\.family))
        let familiesHeld = Set(collection.families.map(\.family))
        self.missingFamilies = familiesFlowering.subtracting(familiesHeld)
            .sorted { $0.scientificName < $1.scientificName }
    }

    public var isEmpty: Bool { inBloom.isEmpty }

    /// One sentence for a notification or a card.
    public var headline: String {
        if let first = notYetPhotographed.first {
            return "\(first.commonName) is out now, and your garden has none."
        }
        if let keystone = keystones.first {
            return "\(keystone.commonName) is flowering — one of the plants that carries a colony through the gaps."
        }
        return "\(inBloom.count) of the flowers your bees work are out this \(season.rawValue)."
    }
}
