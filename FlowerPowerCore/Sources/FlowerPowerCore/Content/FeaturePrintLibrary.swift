//
//  FeaturePrintLibrary.swift
//  FlowerPowerCore
//
//  Naming a flower without training a model.
//
//  The obvious way to identify a species is to train a classifier, and
//  `docs/CLASSIFIER.md` is the brief for doing that. It needs a labelled
//  dataset of thirty British bee-forage species, which does not exist off the
//  shelf — Oxford 102 covers about six of them — so it is real work before
//  there is anything to ship.
//
//  This is the other way. Vision will hand back a *feature print* for any
//  image: a vector from the upper layers of a network Apple already trained,
//  describing what is in the picture. Two photographs of the same flower land
//  near each other in that space, and two photographs of different flowers do
//  not. So a modest set of labelled reference photographs plus a
//  nearest-neighbour lookup is a working classifier, with no training step, no
//  dataset pipeline, and no model to ship.
//
//  It is less accurate than a trained model would be, and that is affordable
//  here in a way it would not be in most apps: identification has always been
//  a *bonus* in this game rather than a gate. A flower it cannot name still
//  feeds the colony, at a lower yield scaled by confidence. A classifier that
//  is right most of the time and honest about the rest fits that exactly.
//
//  The library also grows. A player who names a flower themselves has just
//  labelled a photograph, and a flower somebody shares arrives with a label
//  and a picture attached. Both are references, so the thing gets better as
//  the game is played.
//
//  Only the arithmetic lives here. Producing a feature print needs Vision,
//  which needs an Apple platform; the app hands the vectors in.
//

import Foundation

/// A vector describing the content of an image.
public struct FeaturePrint: Codable, Equatable, Sendable {

    public let values: [Float]

    public init(_ values: [Float]) {
        self.values = values
    }

    public var isEmpty: Bool { values.isEmpty }

    /// Straight-line distance, which is what Vision's own comparison uses.
    ///
    /// Returns `nil` for prints that cannot be compared. Vision's feature
    /// print length depends on which revision produced it, and comparing a
    /// vector of one length against another by truncating would produce a
    /// number that looks like a distance and means nothing.
    public func distance(to other: FeaturePrint) -> Float? {
        guard !values.isEmpty, values.count == other.values.count else { return nil }

        var sum: Float = 0
        for index in values.indices {
            let difference = values[index] - other.values[index]
            sum += difference * difference
        }
        return sum.squareRoot()
    }
}

/// One labelled photograph.
public struct SpeciesReference: Codable, Equatable, Sendable {

    public let speciesID: String
    public let print: FeaturePrint
    /// Where the label came from, which is how much it should be trusted.
    public let source: Source

    public enum Source: String, Codable, Sendable {
        /// Shipped with the app.
        case bundled
        /// The player named this one themselves.
        case named
        /// Arrived with a flower somebody shared.
        case received
    }

    public init(speciesID: String, print: FeaturePrint, source: Source = .bundled) {
        self.speciesID = speciesID
        self.print = print
        self.source = source
    }
}

// MARK: -

public struct FeaturePrintLibrary: Codable, Sendable {

    public private(set) var references: [SpeciesReference]

    /// How many neighbours vote.
    ///
    /// Small, because the library is small — with only a handful of examples
    /// per species, a large k reaches past the right answer into other
    /// species and turns a confident call into a muddle.
    public var neighbours: Int = 5

    /// Beyond this, the nearest reference is not close enough to mean
    /// anything and the answer is "a flower, but we cannot name it".
    ///
    /// The single most important number here, and the one to tune first
    /// against real photographs. Too high and the classifier confidently names
    /// things it has never seen — which is worse than saying nothing, because
    /// a patch identified as the wrong species gets the wrong nectar richness
    /// and the wrong bloom season, and the player is told something plainly
    /// false about the world. Too low and it never names anything, which costs
    /// only the bonus.
    ///
    /// It errs high deliberately. Feature-print distances are not normalised
    /// across Vision revisions, so this wants measuring on device rather than
    /// trusting.
    public var maximumDistance: Float = 1.1

    /// How many references any one species may keep.
    ///
    /// The library grows as the game is played, and without a cap a player who
    /// photographs a great deal of clover would end up with a library that is
    /// mostly clover — which makes every lookup slower *and* biases the vote
    /// toward whatever they photograph most.
    public var referencesPerSpecies: Int = 24

    public init(references: [SpeciesReference] = []) {
        self.references = references
    }

    public var isEmpty: Bool { references.isEmpty }

    public var speciesCovered: Set<String> {
        Set(references.map(\.speciesID))
    }

    // MARK: - Growing

    /// Adds a labelled photograph.
    ///
    /// The oldest reference for a species is dropped once it is full, rather
    /// than the newest being refused, so the library tracks what the player is
    /// actually photographing — a camera, a place, a season.
    public mutating func add(_ reference: SpeciesReference) {
        guard !reference.print.isEmpty else { return }
        references.append(reference)

        let forSpecies = references.enumerated()
            .filter { $0.element.speciesID == reference.speciesID }

        guard forSpecies.count > referencesPerSpecies else { return }

        // Bundled references are the ones that were curated, so they are the
        // last to go rather than the first.
        let removable = forSpecies
            .filter { $0.element.source != .bundled }
            .map(\.offset)

        let excess = forSpecies.count - referencesPerSpecies
        let doomed = Set(removable.prefix(excess))
        guard !doomed.isEmpty else { return }

        references = references.enumerated()
            .filter { !doomed.contains($0.offset) }
            .map(\.element)
    }

    // MARK: - Looking up

    public struct Match: Equatable, Sendable {
        public let speciesID: String
        /// 0...1, and meant to be read as "how much to trust this".
        public let confidence: Double
        /// Distance to the closest reference for this species, for debugging
        /// and for tuning `maximumDistance` against real photographs.
        public let nearestDistance: Float
    }

    /// Best guesses for a photograph, most likely first.
    ///
    /// Empty when nothing is close enough, which is a real answer rather than
    /// a failure: the game is built so that an unnamed flower still works.
    public func matches(for print: FeaturePrint) -> [Match] {
        guard !print.isEmpty, !references.isEmpty else { return [] }

        let scored: [(reference: SpeciesReference, distance: Float)] = references
            .compactMap { reference in
                guard let distance = print.distance(to: reference.print) else { return nil }
                return (reference, distance)
            }
            .sorted { $0.distance < $1.distance }

        guard let nearest = scored.first, nearest.distance <= maximumDistance else {
            return []
        }

        let voters = scored.prefix(max(1, neighbours))

        // Weighted by proximity: a reference sitting almost on top of the
        // photograph should count for more than one at the edge of the
        // neighbourhood. The epsilon keeps an exact match from dividing by
        // zero and taking the whole vote to infinity.
        var weightBySpecies: [String: Double] = [:]
        var nearestBySpecies: [String: Float] = [:]
        var total = 0.0

        for (reference, distance) in voters {
            let weight = 1.0 / (Double(distance) + 0.05)
            weightBySpecies[reference.speciesID, default: 0] += weight
            total += weight

            let existing = nearestBySpecies[reference.speciesID] ?? .greatestFiniteMagnitude
            nearestBySpecies[reference.speciesID] = min(existing, distance)
        }

        guard total > 0 else { return [] }

        // Share of the vote is how *decisive* the neighbourhood was; the
        // distance term is how *close* it was. Both have to be good. A
        // unanimous vote among references that are all far away is a
        // confident answer about a photograph of something else entirely.
        let closeness = Double(1 - min(1, nearest.distance / maximumDistance))

        return weightBySpecies
            .map { speciesID, weight in
                Match(
                    speciesID: speciesID,
                    confidence: min(1, max(0, (weight / total) * closeness)),
                    nearestDistance: nearestBySpecies[speciesID] ?? nearest.distance
                )
            }
            .sorted { lhs, rhs in
                lhs.confidence == rhs.confidence
                    ? lhs.nearestDistance < rhs.nearestDistance
                    : lhs.confidence > rhs.confidence
            }
    }

    /// Resolves matches against the catalogue, dropping any species the
    /// catalogue does not have.
    public func identifications(for print: FeaturePrint) -> [(species: FlowerSpecies, confidence: Double)] {
        matches(for: print).compactMap { match in
            guard let species = FlowerCatalogue.species(withID: match.speciesID) else {
                return nil
            }
            return (species, match.confidence)
        }
    }
}
