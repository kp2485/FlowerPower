//
//  TaxonEmbeddingIndex.swift
//  FlowerPowerCore
//
//  Every flowering plant the identifier knows, as vectors.
//
//  BioCLIP 2 maps a photograph and the text of a taxonomic name into the same
//  space, so identifying a flower is: embed the picture, and find the names
//  whose vectors point the same way. The image half needs Core ML and lives
//  in the app. This is the other half — the matrix of name vectors and the
//  arithmetic that turns "these are the nearest names" into a placement at a
//  rank the game can trust. It is here, in the package, for the same reason
//  `FeaturePrintLibrary` is: it is the part that can be quietly wrong, and it
//  should be tested where tests run.
//
//  The matrix is built by `tools/bioclip/build.py` from the model's own
//  published text embeddings: about 42,000 species, every genus and every
//  family of flowering plant. Species rows are the official vectors; a genus
//  or family row is the normalised mean of its members', which is how one
//  makes a class prototype in a CLIP space and is what lets a photograph of a
//  species the list lacks still land on its genus.
//
//  On ranks
//  --------
//  The model is asked three questions, not one: which species, which genus,
//  which family — each a softmax over that rank's rows, with the species
//  answer also summed up into the genera and families it implies. The finest
//  rank whose best answer clears its threshold is the placement. That is the
//  same shape of honesty the rest of the game runs on: a family is a real
//  answer, and being told the rank beats a confident guess at a species.
//
//  Thresholds were set by reasoning and want tuning against photographs
//  taken the way players take them. `place(_:)` returns every rank's best
//  candidate and score so the tuning can be done by looking.
//

import Foundation

public struct TaxonEmbeddingIndex: Sendable {

    // MARK: - What is in it

    public struct Entry: Hashable, Sendable {
        public let rank: TaxonomicRank
        public let family: String
        public let genus: String
        public let epithet: String
        public let commonName: String

        public var taxon: Taxon {
            Taxon(
                family: BotanicalFamily(family),
                genus: genus.isEmpty ? nil : genus,
                specificEpithet: epithet.isEmpty ? nil : epithet
            )
        }

        /// "Tulipa gesneriana", "Tulipa sp." or "Liliaceae".
        public var scientificName: String { taxon.scientificName }
    }

    public let entries: [Entry]
    public let dimensions: Int
    /// The model's temperature: cosine similarities are multiplied by this
    /// before the softmax, as CLIP does.
    public let logitScale: Float

    /// Row-major int8, `entries.count * dimensions`, each row scaled by the
    /// matching entry of `scales`.
    private let weights: [Int8]
    private let scales: [Float]

    // MARK: - Thresholds

    /// The least probability a rank's best candidate needs before the
    /// placement stops there.
    ///
    /// Species is the strictest because a wrong species is the costliest
    /// mistake the game can make, and because garden plants are cultivars:
    /// a bedding peony is *Paeonia lactiflora*, and the model, offered only
    /// wild species, will pick the nearest wild peony at sixty percent. At
    /// seventy it says *Paeonia* instead, which is true. A wrong family is
    /// rare once the softmax has been summed up the tree.
    ///
    /// Set from ten Wikimedia photographs on 2026-09-16; see
    /// docs/CLASSIFIER.md. Wants tuning on a phone.
    public var speciesThreshold: Float = 0.7
    /// Above a half because summed evidence can pool in a lookalike: the
    /// Phalaenopsis orchid's mass gathered under Paphiopedilum at 57%,
    /// where the family answer was Orchidaceae at 92% and true.
    public var genusThreshold: Float = 0.6
    public var familyThreshold: Float = 0.4

    /// How much a family's own row counts against the species evidence
    /// summed into it. The family rows are means of their members and turn
    /// out to be the weakest signal in the index — on a daffodil the
    /// Ranunculaceae row scored 69% while the summed narcissi scored 97% —
    /// so the direct answer is discounted rather than trusted outright.
    public var familyRowWeight: Float = 0.5

    // MARK: - Loading

    public enum LoadError: Error, Equatable {
        case badMagic
        case unsupportedVersion(UInt32)
        case truncated
        case namesDoNotMatch(rows: Int, names: Int)
        case badRank(String)
    }

    private static let magic: [UInt8] = Array("BCTX".utf8)

    /// Reads `BioCLIPTaxa.bin` and `BioCLIPTaxa.json` as `build.py` writes them.
    public init(matrix: Data, names: Data) throws {
        guard matrix.count >= 20, Array(matrix.prefix(4)) == Self.magic else {
            throw LoadError.badMagic
        }
        let version = matrix.readUInt32(at: 4)
        guard version == 1 else { throw LoadError.unsupportedVersion(version) }
        let rows = Int(matrix.readUInt32(at: 8))
        let dims = Int(matrix.readUInt32(at: 12))
        let scale = Float(bitPattern: matrix.readUInt32(at: 16))

        let weightsStart = 20
        let scalesStart = weightsStart + rows * dims
        guard matrix.count >= scalesStart + rows * 4 else { throw LoadError.truncated }

        weights = matrix.withUnsafeBytes { raw in
            Array(raw[weightsStart..<scalesStart].bindMemory(to: Int8.self))
        }
        scales = (0..<rows).map { row in
            Float(bitPattern: matrix.readUInt32(at: scalesStart + row * 4))
        }

        let decoded = try JSONDecoder().decode([[String]].self, from: names)
        guard decoded.count == rows else {
            throw LoadError.namesDoNotMatch(rows: rows, names: decoded.count)
        }
        entries = try decoded.map { fields in
            guard fields.count == 5 else { throw LoadError.truncated }
            let rank: TaxonomicRank
            switch fields[0] {
            case "s": rank = .species
            case "g": rank = .genus
            case "f": rank = .family
            default: throw LoadError.badRank(fields[0])
            }
            return Entry(
                rank: rank, family: fields[1], genus: fields[2],
                epithet: fields[3], commonName: fields[4]
            )
        }

        dimensions = dims
        logitScale = scale
    }

    /// For tests: an index built from plain vectors.
    public init(entries: [Entry], vectors: [[Float]], logitScale: Float = 100) {
        precondition(entries.count == vectors.count)
        self.entries = entries
        self.dimensions = vectors.first?.count ?? 0
        self.logitScale = logitScale

        var weights: [Int8] = []
        var scales: [Float] = []
        weights.reserveCapacity(entries.count * dimensions)
        for vector in vectors {
            let largest = vector.map(abs).max() ?? 0
            let scale = largest > 0 ? largest / 127 : 1
            scales.append(scale)
            weights.append(contentsOf: vector.map { Int8((($0 / scale).rounded()).clamped(to: -127...127)) })
        }
        self.weights = weights
        self.scales = scales
    }

    public var isEmpty: Bool { entries.isEmpty }

    // MARK: - Scoring

    /// One rank's best answer.
    public struct Candidate: Equatable, Sendable {
        public let entry: Entry
        /// 0...1 within its rank.
        public let probability: Float
    }

    /// Everything the index thinks about a photograph.
    public struct Placement: Equatable, Sendable {
        /// The finest rank that cleared its threshold, or nil when none did.
        public let taxon: Taxon?
        /// Confidence at `taxon`'s rank.
        public let confidence: Double
        /// The common name of what was placed, when the row had one.
        public let commonName: String?
        /// Runners-up at the placed rank, best first.
        public let alternatives: [Candidate]
        /// The best candidate at each rank regardless of thresholds, for
        /// tuning and for telling the player what the runner-up was.
        public let bestSpecies: Candidate?
        public let bestGenus: Candidate?
        public let bestFamily: Candidate?
    }

    /// Cosine similarity of the photograph with every row, times the logit
    /// scale. The photograph's embedding is expected unit-length, as the
    /// image tower emits it.
    public func logits(for embedding: [Float]) -> [Float] {
        guard embedding.count == dimensions, dimensions > 0 else { return [] }
        let rows = entries.count
        var out = [Float](repeating: 0, count: rows)

        weights.withUnsafeBufferPointer { w in
            embedding.withUnsafeBufferPointer { q in
                for row in 0..<rows {
                    let base = row * dimensions
                    var sum: Float = 0
                    // Four accumulators, so the loop is not one long
                    // dependency chain. The compiler vectorises the rest.
                    var s0: Float = 0, s1: Float = 0, s2: Float = 0, s3: Float = 0
                    var i = 0
                    while i + 4 <= dimensions {
                        s0 += Float(w[base + i]) * q[i]
                        s1 += Float(w[base + i + 1]) * q[i + 1]
                        s2 += Float(w[base + i + 2]) * q[i + 2]
                        s3 += Float(w[base + i + 3]) * q[i + 3]
                        i += 4
                    }
                    while i < dimensions {
                        s0 += Float(w[base + i]) * q[i]
                        i += 1
                    }
                    sum = s0 + s1 + s2 + s3
                    out[row] = sum * scales[row] * logitScale
                }
            }
        }
        return out
    }

    /// Places a photograph as precisely as the scores honestly allow.
    public func place(_ embedding: [Float]) -> Placement? {
        let logits = logits(for: embedding)
        guard !logits.isEmpty else { return nil }

        // A softmax within each rank.
        var probabilities = [Float](repeating: 0, count: logits.count)
        for rank in TaxonomicRank.allCases {
            var largest = -Float.greatestFiniteMagnitude
            for (i, entry) in entries.enumerated() where entry.rank == rank {
                largest = max(largest, logits[i])
            }
            var total: Float = 0
            for (i, entry) in entries.enumerated() where entry.rank == rank {
                let p = exp(logits[i] - largest)
                probabilities[i] = p
                total += p
            }
            guard total > 0 else { continue }
            for (i, entry) in entries.enumerated() where entry.rank == rank {
                probabilities[i] /= total
            }
        }

        // The species answer, summed up the tree. A photograph of a species
        // the list lacks scatters its probability across lookalikes, which
        // are usually its own genus and almost always its own family, so the
        // sums are more trustworthy than the species row itself.
        var genusMass: [String: Float] = [:]
        var familyMass: [String: Float] = [:]
        for (i, entry) in entries.enumerated() where entry.rank == .species {
            genusMass[entry.family + "/" + entry.genus, default: 0] += probabilities[i]
            familyMass[entry.family, default: 0] += probabilities[i]
        }

        // Each rank's score is the better of the direct row and the summed
        // evidence from below, with the family row discounted.
        var scored: [(index: Int, score: Float)] = []
        scored.reserveCapacity(entries.count)
        for (i, entry) in entries.enumerated() {
            let direct = probabilities[i]
            let score: Float
            switch entry.rank {
            case .species:
                score = direct
            case .genus:
                score = max(direct, genusMass[entry.family + "/" + entry.genus] ?? 0)
            case .family:
                score = max(direct * familyRowWeight, familyMass[entry.family] ?? 0)
            }
            scored.append((i, score))
        }

        func best(at rank: TaxonomicRank, count: Int) -> [Candidate] {
            scored
                .filter { entries[$0.index].rank == rank }
                .sorted { $0.score > $1.score }
                .prefix(count)
                .map { Candidate(entry: entries[$0.index], probability: min(1, $0.score)) }
        }

        let species = best(at: .species, count: 4)
        let genera = best(at: .genus, count: 4)
        let families = best(at: .family, count: 4)

        let placed: [Candidate]
        if let top = species.first, top.probability >= speciesThreshold {
            placed = species
        } else if let top = genera.first, top.probability >= genusThreshold {
            placed = genera
        } else if let top = families.first, top.probability >= familyThreshold {
            placed = families
        } else {
            placed = []
        }

        return Placement(
            taxon: placed.first?.entry.taxon,
            confidence: Double(placed.first?.probability ?? 0),
            commonName: placed.first.flatMap { $0.entry.commonName.isEmpty ? nil : $0.entry.commonName },
            alternatives: Array(placed.dropFirst()),
            bestSpecies: species.first,
            bestGenus: genera.first,
            bestFamily: families.first
        )
    }

    // MARK: - Looking names up

    /// Entries whose names contain the query, for a player naming a flower
    /// themselves. Species first, then genera, then families; a short query
    /// matches many things, so the caller should cap what it shows.
    public func search(_ query: String, limit: Int = 50) -> [Entry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard needle.count >= 2 else { return [] }

        var found: [Entry] = []
        for entry in entries {
            if entry.commonName.lowercased().contains(needle)
                || entry.scientificName.lowercased().contains(needle)
                || (entry.rank == .family && entry.family.lowercased().contains(needle)) {
                found.append(entry)
                if found.count >= limit * 4 { break }
            }
        }
        return Array(found
            .sorted { lhs, rhs in
                // An exact hit on a common name goes first; then finer ranks.
                let l = lhs.commonName.lowercased() == needle
                let r = rhs.commonName.lowercased() == needle
                if l != r { return l }
                if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
                return lhs.scientificName < rhs.scientificName
            }
            .prefix(limit))
    }
}

// MARK: - Bytes

private extension Data {
    func readUInt32(at offset: Int) -> UInt32 {
        let start = startIndex + offset
        return withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: start - startIndex, as: UInt32.self)
        }.littleEndian
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
