import Foundation
import Testing
@testable import FlowerPowerCore

/// Families beyond the catalogue, the operating system's labels, and the
/// embedding index: the three things that let the game name a flower it has
/// never modelled.
@Suite("Open taxonomy")
struct OpenTaxonomyTests {

    // MARK: - Any family at all

    @Test("A modelled family is recognised by name, whatever the case")
    func knownFamily() {
        #expect(BotanicalFamily("Asteraceae").known == .asteraceae)
        #expect(BotanicalFamily(" ASTERACEAE ").known == .asteraceae)
        #expect(BotanicalFamily("Orchidaceae").known == nil)
    }

    @Test("A family the game does not model still has a name and traits")
    func unknownFamily() {
        let orchids = BotanicalFamily("Orchidaceae")
        #expect(orchids.scientificName == "Orchidaceae")
        #expect(orchids.commonName == "Orchid Family")
        #expect(orchids.typicalTraits.isOutOfReach || orchids.typicalTraits.pollenAbundance < 0.5)

        let obscure = BotanicalFamily("Cyclanthaceae")
        #expect(obscure.commonName == "Cyclanthaceae")
        #expect(obscure.typicalTraits == FloralTraits.unknownFamily)
        #expect(!obscure.forageNote.isEmpty)
    }

    @Test("A genus offered as a family is not well formed")
    func wellFormed() {
        #expect(BotanicalFamily("Rosaceae").isWellFormed)
        #expect(!BotanicalFamily("Rosa").isWellFormed)
        #expect(!BotanicalFamily("").isWellFormed)
    }

    @Test("A modelled family compares equal to its name")
    func equality() {
        #expect(Taxon(family: .fabaceae).family == .fabaceae)
        #expect(Taxon(family: BotanicalFamily("Fabaceae")).family == .fabaceae)
        #expect(Taxon(family: BotanicalFamily("Orchidaceae")).family != .fabaceae)
        #expect(Taxon(family: .fabaceae) == Taxon(family: BotanicalFamily("fabaceae")))
    }

    /// The save file used to hold the enum's raw value. It must read back.
    @Test("A placement encodes as it always did")
    func codable() throws {
        let clover = Taxon(family: .fabaceae, genus: "Trifolium", specificEpithet: "repens")
        let json = try JSONEncoder().encode(clover)
        let text = try #require(String(data: json, encoding: .utf8))
        #expect(text.contains("\"family\":\"fabaceae\""))
        #expect(try JSONDecoder().decode(Taxon.self, from: json) == clover)

        let legacy = Data("{\"family\":\"boraginaceae\",\"genus\":\"Borago\"}".utf8)
        let decoded = try JSONDecoder().decode(Taxon.self, from: legacy)
        #expect(decoded.family == .boraginaceae)
        #expect(decoded.rank == .genus)

        let foreign = Data("{\"family\":\"liliaceae\",\"genus\":\"Tulipa\"}".utf8)
        let tulip = try JSONDecoder().decode(Taxon.self, from: foreign)
        #expect(tulip.family.known == nil)
        #expect(tulip.scientificName == "Tulipa sp.")
    }

    @Test("A generic species for an unmodelled family carries the family's traits and the identifier's name")
    func genericBeyondCatalogue() {
        let taxon = Taxon(family: BotanicalFamily("Paeoniaceae"), genus: "Paeonia", specificEpithet: "lactiflora")
        let peony = FlowerSpecies.generic(for: taxon, commonName: "Chinese peony")
        #expect(peony.commonName == "Chinese peony")
        #expect(peony.scientificName == "Paeonia lactiflora")
        #expect(!peony.traits.producesNectar)
        #expect(peony.family.commonName == "Peony Family")

        let unnamed = FlowerSpecies.generic(for: taxon)
        #expect(unnamed.commonName == "Paeonia lactiflora")

        let family = FlowerSpecies.generic(for: Taxon(family: BotanicalFamily("Paeoniaceae")), commonName: "ignored")
        #expect(family.commonName == "Peony Family")
    }

    // MARK: - World families

    @Test("Every world family is a real family name, and none duplicates a modelled one")
    func worldFamiliesAreWellFormed() {
        for family in WorldFamilies.known {
            #expect(family.isWellFormed, "\(family.rawValue)")
            #expect(family.known == nil, "\(family.rawValue) is already modelled")
            let entry = WorldFamilies.entry(for: family)!
            #expect(!entry.commonName.isEmpty)
            #expect(!entry.forageNote.isEmpty)
            if !entry.traits.producesNectar {
                #expect(entry.traits.nectarVolume == 0)
            }
        }
        #expect(WorldFamilies.known.count >= 40)
    }

    // MARK: - Vision's labels

    @Test("Every label resolves to a species with a coherent taxon")
    func visionLabelsResolve() {
        for (label, target) in VisionLabelTaxa.table {
            let species = VisionLabelTaxa.species(forLabel: label)
            #expect(species != nil, "\(label)")
            if case .catalogue(let id) = target {
                #expect(species?.id == id)
            }
        }
        #expect(VisionLabelTaxa.species(forLabel: "toaster") == nil)
        #expect(VisionLabelTaxa.species(forLabel: "SUNFLOWER")?.id == "sunflower")
    }

    @Test("A catalogue plant named by label gets the catalogue's traits")
    func visionLabelUsesCatalogue() {
        let rosemary = VisionLabelTaxa.species(forLabel: "rosemary")
        #expect(rosemary == FlowerCatalogue.species(withID: "rosemary"))

        let tulip = VisionLabelTaxa.species(forLabel: "tulip")
        #expect(tulip?.taxon.rank == .genus)
        #expect(tulip?.family.commonName == "Lily Family")
    }

    // MARK: - The embedding index

    private static func entry(_ rank: TaxonomicRank, _ family: String, _ genus: String = "", _ epithet: String = "", common: String = "") -> TaxonEmbeddingIndex.Entry {
        TaxonEmbeddingIndex.Entry(rank: rank, family: family, genus: genus, epithet: epithet, commonName: common)
    }

    /// A toy space: a few unit vectors in eight dimensions.
    private static func unit(_ axis: Int, _ second: Int? = nil, weight: Float = 0) -> [Float] {
        var v = [Float](repeating: 0, count: 8)
        v[axis] = 1
        if let second { v[second] = weight }
        let norm = sqrt(v.map { $0 * $0 }.reduce(0, +))
        return v.map { $0 / norm }
    }

    /// Three genera of two species each, so that "nothing is close" spreads
    /// its probability thinly enough to clear no threshold — as it does in
    /// the real index, where a genus is one of fourteen thousand.
    private static func toyIndex() -> TaxonEmbeddingIndex {
        let entries = [
            entry(.species, "Liliaceae", "Tulipa", "gesneriana", common: "Garden tulip"),
            entry(.species, "Liliaceae", "Tulipa", "sylvestris"),
            entry(.species, "Rosaceae", "Rosa", "canina", common: "Dog rose"),
            entry(.species, "Rosaceae", "Rosa", "rugosa"),
            entry(.species, "Papaveraceae", "Papaver", "rhoeas"),
            entry(.species, "Papaveraceae", "Papaver", "somniferum"),
            entry(.genus, "Liliaceae", "Tulipa"),
            entry(.genus, "Rosaceae", "Rosa"),
            entry(.genus, "Papaveraceae", "Papaver"),
            entry(.family, "Liliaceae"),
            entry(.family, "Rosaceae"),
            entry(.family, "Papaveraceae")
        ]
        let vectors = [
            unit(0), unit(1), unit(2), unit(3), unit(4), unit(5),
            unit(0, 1, weight: 1), unit(2, 3, weight: 1), unit(4, 5, weight: 1),
            unit(0, 1, weight: 1), unit(2, 3, weight: 1), unit(4, 5, weight: 1)
        ]
        return TaxonEmbeddingIndex(entries: entries, vectors: vectors, logitScale: 100)
    }

    /// Two tulips half-seen and nothing else: the species split cannot clear
    /// its threshold, the genus sum can, and the family follows from the
    /// summed species rather than from its own discounted row.
    @Test("Family evidence is the species evidence summed, not the family's own row")
    func familyFromSummedSpecies() throws {
        let index = Self.toyIndex()
        let placement = try #require(index.place(Self.unit(0, 1, weight: 1)))
        #expect(placement.bestFamily?.entry.family == "Liliaceae")
        #expect(placement.bestFamily!.probability > 0.9)
    }

    @Test("A photograph that sits on a species is placed to that species, with its common name")
    func speciesPlacement() throws {
        let index = Self.toyIndex()
        let placement = try #require(index.place(Self.unit(0)))
        #expect(placement.taxon?.scientificName == "Tulipa gesneriana")
        #expect(placement.commonName == "Garden tulip")
        #expect(placement.confidence > 0.9)
        #expect(placement.alternatives.first?.entry.epithet == "sylvestris")
    }

    /// Half way between two tulips is not either tulip, but it is plainly a
    /// tulip: the species probability is split, and the genus sum is not.
    @Test("A photograph between two species of a genus is placed to the genus")
    func genusPlacement() throws {
        let index = Self.toyIndex()
        let placement = try #require(index.place(Self.unit(0, 1, weight: 1)))
        #expect(placement.taxon?.rank == .genus)
        #expect(placement.taxon?.scientificName == "Tulipa sp.")
        #expect(placement.bestSpecies!.probability < index.speciesThreshold)
        #expect(placement.confidence >= Double(index.genusThreshold))
    }

    @Test("A photograph of nothing in the index is not placed")
    func nothingClose() throws {
        let index = Self.toyIndex()
        let placement = try #require(index.place(Self.unit(7)))
        #expect(placement.taxon == nil)
        #expect(placement.confidence == 0)
    }

    @Test("A wrong-sized embedding yields nothing rather than nonsense")
    func wrongDimensions() {
        let index = Self.toyIndex()
        #expect(index.logits(for: [1, 0]).isEmpty)
        #expect(index.place([1, 0]) == nil)
    }

    @Test("Search finds names by common name, Latin and family, finest rank first")
    func search() {
        let index = Self.toyIndex()
        let tulips = index.search("tulip")
        #expect(tulips.first?.commonName == "Garden tulip")
        #expect(tulips.contains { $0.rank == .genus && $0.genus == "Tulipa" })
        #expect(index.search("rosa").contains { $0.rank == .species })
        #expect(index.search("liliaceae").contains { $0.rank == .family })
        #expect(index.search("t").isEmpty)
    }

    /// The binary format `build.py` writes, hand-assembled.
    @Test("The matrix file is read as written")
    func binaryFormat() throws {
        var data = Data("BCTX".utf8)
        func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        append(1)      // version
        append(2)      // rows
        append(3)      // dims
        append(Float(50).bitPattern)
        data.append(contentsOf: [127, 0, 0, 0, 127, 0].map { UInt8(bitPattern: Int8($0)) })
        append((Float(1) / 127).bitPattern)
        append((Float(1) / 127).bitPattern)
        let names = Data("[[\"s\",\"Rosaceae\",\"Rosa\",\"canina\",\"Dog rose\"],[\"f\",\"Rosaceae\",\"\",\"\",\"\"]]".utf8)

        let index = try TaxonEmbeddingIndex(matrix: data, names: names)
        #expect(index.entries.count == 2)
        #expect(index.dimensions == 3)
        #expect(index.logitScale == 50)
        #expect(index.entries[0].taxon.scientificName == "Rosa canina")
        #expect(index.entries[1].rank == .family)

        let logits = index.logits(for: [1, 0, 0])
        #expect(abs(logits[0] - 50) < 0.01)
        #expect(abs(logits[1]) < 0.01)

        #expect(throws: TaxonEmbeddingIndex.LoadError.badMagic) {
            try TaxonEmbeddingIndex(matrix: Data("nope".utf8), names: names)
        }
        #expect(throws: TaxonEmbeddingIndex.LoadError.namesDoNotMatch(rows: 2, names: 1)) {
            try TaxonEmbeddingIndex(matrix: data, names: Data("[[\"s\",\"Rosaceae\",\"Rosa\",\"canina\",\"\"]]".utf8))
        }
    }
}
