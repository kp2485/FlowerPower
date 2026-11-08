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

    /// Each entry's names, lowercased once at load and joined with a
    /// separator at both ends, so a search is substring tests on one string
    /// rather than three `lowercased()` copies per entry per keystroke.
    private let searchKeys: [String]

    private static let separator: Character = "\u{1}"

    private static func searchKeys(for entries: [Entry]) -> [String] {
        entries.map { entry in
            var names = [entry.commonName, entry.scientificName]
            // Only a family's own row answers to the family's name; otherwise
            // "rosaceae" matched every one of its five thousand species.
            if entry.rank == .family { names.append(entry.family) }
            let joined = names.filter { !$0.isEmpty }
                .map { $0.lowercased() }
                .joined(separator: String(separator))
            return String(separator) + joined + String(separator)
        }
    }

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

    /// The least probability a member needs to be offered as a narrower
    /// guess under a genus or family placement. Below it the guess is one of
    /// dozens of equals, and naming it would pretend otherwise.
    public var narrowerFloor: Float = 0.05

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
        let listed = try decoded.map { fields -> Entry in
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

        entries = Self.naming(listed)
        dimensions = dims
        logitScale = scale
        searchKeys = Self.searchKeys(for: entries)
    }

    /// For tests: an index built from plain vectors.
    public init(entries: [Entry], vectors: [[Float]], logitScale: Float = 100) {
        precondition(entries.count == vectors.count)
        let entries = Self.naming(entries)
        self.entries = entries
        self.searchKeys = Self.searchKeys(for: entries)
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

    // MARK: - Names for genera and families

    /// Last words that say what sort of plant something is rather than which:
    /// "tulip tree" is not a tree genus, so these keep the word before them.
    private static let vagueHeads: Set<String> = [
        "tree", "plant", "flower", "bush", "shrub", "weed", "herb", "vine",
        "grass", "wort", "root", "leaf", "creeper", "climber"
    ]

    /// The names a player can read, filled in where the list has none.
    ///
    /// `build.py` gives common names to species only, and only to about half
    /// of them, so every genus and family came back in Latin: a photograph of
    /// a tulip placed to its genus was titled "Tulipa sp.", which read as the
    /// identifier giving up part of the way. A genus is named here from its
    /// species — most roses are "something rose" — and a family from the
    /// game's own notes or its type genus, the way English does it ("Acanthus
    /// Family"). Wherever that would be a guess, the Latin genus is the name,
    /// because it is what a gardener calls a hibiscus or a eucalyptus anyway,
    /// and it is never wrong.
    ///
    /// Species names that are not plain ASCII are dropped first. The list
    /// mixes in Swedish and Korean names ("maskros", "단풍취"), and those
    /// were shown as if they were English.
    static func naming(_ raw: [Entry]) -> [Entry] {
        let entries = raw.map { entry -> Entry in
            guard entry.rank == .species, !entry.commonName.allSatisfy(\.isASCII) else { return entry }
            return Entry(rank: entry.rank, family: entry.family, genus: entry.genus,
                         epithet: entry.epithet, commonName: "")
        }

        var named: [String: [String]] = [:]
        var speciesCount: [String: Int] = [:]
        var generaByFamily: [String: [String]] = [:]
        for entry in entries {
            let key = entry.family + "/" + entry.genus
            switch entry.rank {
            case .species:
                speciesCount[key, default: 0] += 1
                if !entry.commonName.isEmpty { named[key, default: []].append(entry.commonName) }
            case .genus:
                generaByFamily[entry.family, default: []].append(entry.genus)
            case .family:
                break
            }
        }

        // The word most of a genus's species end in, where most of them
        // share one: "rose" for Rosa, "clover" for Trifolium.
        var heads: [String: (word: String, count: Int)] = [:]
        for (key, names) in named where names.count >= 2 {
            var counts: [String: Int] = [:]
            for name in names {
                let words = name.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
                guard var head = words.last else { continue }
                if vagueHeads.contains(head), words.count >= 2 { head = words[words.count - 2] + " " + head }
                counts[head, default: 0] += 1
            }
            let genus = String(key.split(separator: "/").last ?? "").lowercased()
            // Where a quarter of the names are the genus's own Latin name
            // ("rhododendron", "hibiscus"), that is what people call it.
            if (counts[genus] ?? 0) * 4 >= names.count { continue }
            guard let best = counts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }),
                  best.value >= 2, best.value * 2 >= names.count
            else { continue }
            heads[key] = (best.key, best.value)
        }

        // A word names only the genus that uses it most. Helicia has two
        // species called "… oak", but an oak is a Quercus.
        var owner: [String: String] = [:]
        for (key, head) in heads.sorted(by: { $0.key < $1.key }) {
            if let current = owner[head.word], heads[current]!.count >= head.count { continue }
            owner[head.word] = key
        }

        func genusName(family: String, genus: String) -> String {
            let key = family + "/" + genus
            let names = named[key] ?? []
            // A genus of one species is that species, and can take its name
            // whole ("Water lettuce"). One named species among several says
            // nothing about the rest: Abeliophyllum's "white forsythia" is
            // not a forsythia.
            if names.count == 1, speciesCount[key] == 1 { return names[0].capitalisingFirst }
            if let head = heads[key], owner[head.word] == key { return head.word.capitalisingFirst }
            return genus
        }

        func familyName(_ family: String) -> String {
            let botanical = BotanicalFamily(family)
            if botanical.commonName != botanical.scientificName { return botanical.commonName }
            guard family.count > 5 else { return "" }
            let stem = family.dropLast(5).lowercased()
            let type = generaByFamily[family, default: []]
                .filter { $0.lowercased().hasPrefix(stem) }
                .min { ($0.count, $0) < ($1.count, $1) }
            return type.map { "\($0) Family" } ?? ""
        }

        return entries.map { entry in
            guard entry.commonName.isEmpty else { return entry }
            let name: String
            switch entry.rank {
            case .species: return entry
            case .genus: name = genusName(family: entry.family, genus: entry.genus)
            case .family: name = familyName(entry.family)
            }
            return Entry(rank: entry.rank, family: entry.family, genus: entry.genus,
                         epithet: entry.epithet, commonName: name)
        }
    }

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
        /// When the placement stopped at a genus or family, the likeliest
        /// members one rank down, best first: the species of the genus, or
        /// the genera of the family. Not placements — none cleared its
        /// threshold — but the guesses a player who knows the plant can
        /// finish the identification with.
        public let narrower: [Candidate]
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

        func members(at rank: TaxonomicRank, of group: Entry) -> [Candidate] {
            scored
                .filter { item in
                    let entry = entries[item.index]
                    return entry.rank == rank && entry.family == group.family
                        && (group.rank == .family || entry.genus == group.genus)
                        && item.score >= narrowerFloor
                }
                .sorted { $0.score > $1.score }
                .prefix(3)
                .map { Candidate(entry: entries[$0.index], probability: min(1, $0.score)) }
        }

        let narrower: [Candidate]
        switch placed.first?.entry {
        case let group? where group.rank == .genus: narrower = members(at: .species, of: group)
        case let group? where group.rank == .family: narrower = members(at: .genus, of: group)
        default: narrower = []
        }

        return Placement(
            taxon: placed.first?.entry.taxon,
            confidence: Double(placed.first?.probability ?? 0),
            commonName: placed.first.flatMap { $0.entry.commonName.isEmpty ? nil : $0.entry.commonName },
            alternatives: Array(placed.dropFirst()),
            narrower: narrower,
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

        let separator = String(Self.separator)
        let whole = separator + needle + separator
        let start = separator + needle
        let word = " " + needle
        // The query as a word of its own inside a longer name: "Garden
        // tulip" for "tulip", "Dog rose" for "rose".
        let wholeWord = [separator, " "].flatMap { before in
            [separator, " "].map { after in before + needle + after }
        }

        // Every entry is scanned, then ranked. The scan used to stop at the
        // first `limit * 4` hits in file order, which is species first — so
        // "rose" filled up on primroses and rosemary and never reached the
        // roses themselves.
        var found: [(index: Int, score: Int)] = []
        for (index, key) in searchKeys.enumerated() where key.contains(needle) {
            let score: Int
            if key.contains(whole) { score = 0 }
            else if wholeWord.contains(where: key.contains) { score = 1 }
            else if key.contains(start) { score = 2 }
            else if key.contains(word) { score = 3 }
            else { score = 4 }
            found.append((index, score))
        }

        return found
            .sorted { lhs, rhs in
                // A whole name first, then a whole word, then a name that
                // starts with it, then a word that does, then anything
                // containing it; finer ranks before coarser within each.
                if lhs.score != rhs.score { return lhs.score < rhs.score }
                let l = entries[lhs.index], r = entries[rhs.index]
                if l.rank != r.rank { return l.rank > r.rank }
                return l.scientificName < r.scientificName
            }
            .prefix(limit)
            .map { entries[$0.index] }
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
