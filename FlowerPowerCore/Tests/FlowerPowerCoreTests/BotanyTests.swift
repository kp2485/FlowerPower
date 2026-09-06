import Testing
@testable import FlowerPowerCore

/// Taxonomy, floral traits, and whether a honey bee can reach the nectar.
///
/// Written with Swift Testing rather than XCTest: it is the framework Apple
/// recommends for new tests, `#expect` reports the actual values without
/// having to be told to, and parameterised cases let one test cover the whole
/// catalogue instead of thirty near-copies. The older suites stay on XCTest —
/// the two coexist in the same target, and rewriting two hundred passing tests
/// to change their spelling would be churn.
@Suite("Botany")
struct BotanyTests {

    // MARK: - Rank

    @Test("A placement knows how precise it is")
    func rank() {
        #expect(Taxon(family: .fabaceae).rank == .family)
        #expect(Taxon(family: .fabaceae, genus: "Trifolium").rank == .genus)
        #expect(
            Taxon(family: .fabaceae, genus: "Trifolium", specificEpithet: "repens").rank
                == .species
        )
    }

    /// A specific epithet with no genus is half a name, not a placement.
    @Test("An epithet without a genus is discarded")
    func epithetWithoutGenus() {
        let broken = Taxon(family: .fabaceae, specificEpithet: "repens")
        #expect(broken.rank == .family)
        #expect(broken.specificEpithet == nil)
    }

    @Test("Names are written the way a botanist writes them")
    func scientificNames() {
        #expect(Taxon(family: .fabaceae).scientificName == "Fabaceae")
        #expect(Taxon(family: .fabaceae, genus: "Trifolium").scientificName == "Trifolium sp.")
        #expect(
            Taxon(family: .fabaceae, genus: "Trifolium", specificEpithet: "repens")
                .scientificName == "Trifolium repens"
        )
    }

    @Test("A coarse placement contains a finer one of the same plant")
    func containment() {
        let clover = Taxon(family: .fabaceae, genus: "Trifolium", specificEpithet: "repens")

        #expect(Taxon(family: .fabaceae).contains(clover))
        #expect(Taxon(family: .fabaceae, genus: "Trifolium").contains(clover))
        #expect(!Taxon(family: .rosaceae).contains(clover))
        #expect(!Taxon(family: .fabaceae, genus: "Lupinus").contains(clover))
    }

    @Test("Ranks are ordered by precision")
    func rankOrdering() {
        #expect(TaxonomicRank.family < TaxonomicRank.genus)
        #expect(TaxonomicRank.genus < TaxonomicRank.species)
    }

    // MARK: - Reach

    /// The fact the whole model turns on. White clover and red clover are the
    /// same genus with comparable nectar; the tube is 2 mm against 9-10, and
    /// that is the entire reason one is the classic honey plant and the other
    /// is famously useless to a honey bee.
    @Test("Corolla depth decides access, not nectar quantity")
    func reach() {
        func traits(depth: Double) -> FloralTraits {
            FloralTraits(
                corollaDepthMillimetres: depth,
                nectarSugarConcentration: 0.4,
                nectarVolume: 2.0,
                pollenProteinFraction: 0.2,
                pollenAminoAcidCompleteness: 1,
                pollenAbundance: 1
            )
        }

        let whiteClover = traits(depth: 2)
        let redClover = traits(depth: 9.5)

        #expect(whiteClover.nectarAccessibility == 1)
        #expect(redClover.nectarAccessibility < 0.4)
        #expect(redClover.effectiveNectarYield < whiteClover.effectiveNectarYield)
    }

    @Test("A flower deeper than a bee can reach yields nothing")
    func outOfReach() {
        let foxglove = FlowerCatalogue.foxglove
        #expect(foxglove.traits.nectarAccessibility == 0)
        #expect(foxglove.nectarIsOutOfReach)
        #expect(foxglove.nectarRichness == 0)

        // But it is still worth visiting.
        #expect(foxglove.pollenRichness > 0)
    }

    @Test(
        "Exactly the plants a honey bee cannot work are out of reach",
        arguments: [
            ("crocus", true), ("foxglove", true), ("poppy", true), ("meadowsweet", true),
            ("white_clover", false), ("ivy", false), ("bramble", false), ("borage", false)
        ]
    )
    func reachAcrossTheCatalogue(id: String, locked: Bool) throws {
        let species = try #require(FlowerCatalogue.species(withID: id))
        #expect(species.nectarIsOutOfReach == locked)
    }

    // MARK: - Nectarless plants

    /// A single richness number could not say this, and had both plants wrong.
    @Test("Poppy and meadowsweet offer pollen and no nectar", arguments: ["poppy", "meadowsweet"])
    func nectarless(id: String) throws {
        let species = try #require(FlowerCatalogue.species(withID: id))

        #expect(!species.traits.producesNectar)
        #expect(species.nectarRichness == 0)
        #expect(species.pollenRichness > 1, "and a great deal of pollen")
    }

    // MARK: - Pollen quality

    /// Dandelion pollen is measurably short of arginine, isoleucine, leucine
    /// and valine. A colony rearing brood on it alone does badly however much
    /// it collects, which quantity alone cannot express.
    @Test("Dandelion is abundant pollen of poor quality")
    func dandelion() {
        let dandelion = FlowerCatalogue.dandelion
        let willow = FlowerCatalogue.willow

        #expect(dandelion.traits.pollenAbundance > 1, "it is not scarce")
        #expect(dandelion.traits.pollenAminoAcidCompleteness < 0.7, "it is incomplete")
        #expect(dandelion.traits.pollenQuality < willow.traits.pollenQuality)
    }

    @Test("Willow is the spring pollen that matters")
    func willow() {
        let willow = FlowerCatalogue.willow
        #expect(willow.pollenRichness > 2)
        #expect(willow.bloomSeasons == [.spring])
        #expect(willow.isKeystone)
    }

    // MARK: - Coarse identification

    /// The point of ranking identification: a photograph placed only in
    /// Boraginaceae is still known to be a good, workable nectar plant.
    @Test("A family-level placement still describes the forage")
    func familyLevelForage() {
        let borages = FlowerSpecies.generic(for: Taxon(family: .boraginaceae))

        #expect(borages.nectarRichness > 1, "the borage family are good nectar plants")
        #expect(!borages.nectarIsOutOfReach)
        #expect(borages.commonName == "Borage Family")
    }

    @Test("A genus-level placement is described by its known members")
    func genusLevelForage() {
        let heathers = FlowerSpecies.generic(
            for: Taxon(family: .ericaceae, genus: "Calluna")
        )
        #expect(heathers.taxon.rank == .genus)
        #expect(heathers.commonName == "Calluna sp.")
    }

    /// A family whose members a honey bee cannot work should say so even
    /// without a species.
    @Test("A family out of reach is out of reach at family level too")
    func familyOutOfReach() {
        let foxgloves = FlowerSpecies.generic(for: Taxon(family: .plantaginaceae))
        #expect(foxgloves.nectarIsOutOfReach)
    }

    @Test("A generic placement never claims to be a catalogue species")
    func genericIsDistinct() {
        let generic = FlowerSpecies.generic(for: Taxon(family: .rosaceae))
        #expect(!FlowerCatalogue.all.contains { $0.id == generic.id })
    }

    // MARK: - Scale

    /// Every consumption constant in the engine — what a colony burns, what it
    /// needs for winter, what counts as a flow — was calibrated against a
    /// forage scale where the mean flower is 1. Deriving nectar and pollen
    /// from real traits changed the size of that unit, so the reference values
    /// are normalised to the catalogue. If the catalogue drifts, this fails
    /// before the balance quietly does.
    @Test("The mean catalogue flower is one forage unit")
    func forageScale() {
        let all = FlowerCatalogue.all
        let nectar = all.map(\.nectarRichness).reduce(0, +) / Double(all.count)
        let pollen = all.map(\.pollenRichness).reduce(0, +) / Double(all.count)

        #expect(abs(nectar - 1) < 0.05, "mean nectar richness is \(nectar)")
        #expect(abs(pollen - 1) < 0.05, "mean pollen richness is \(pollen)")
    }

    // MARK: - The catalogue itself

    @Test("Every species is placed to a species", arguments: FlowerCatalogue.all)
    func everySpeciesIsFullyPlaced(species: FlowerSpecies) {
        #expect(species.taxon.rank == .species, "\(species.commonName) is not placed to a species")
        #expect(species.scientificName?.isEmpty == false)
    }

    @Test("Traits are physically plausible", arguments: FlowerCatalogue.all)
    func traitsArePlausible(species: FlowerSpecies) {
        let traits = species.traits

        #expect(traits.corollaDepthMillimetres >= 0)
        #expect(traits.corollaDepthMillimetres < 60, "no British bee plant has a tube that deep")
        #expect((0...1).contains(traits.nectarSugarConcentration))
        #expect((0.10...0.35).contains(traits.pollenProteinFraction),
                "crude protein outside the range plants actually offer")
        #expect((0...1).contains(traits.pollenAminoAcidCompleteness))
        #expect(traits.pollenAbundance > 0, "every flower offers some pollen")
    }

    /// A nectarless plant should have no nectar traits pretending otherwise.
    @Test("Nectarless plants are consistently nectarless", arguments: FlowerCatalogue.all)
    func nectarlessConsistency(species: FlowerSpecies) {
        guard !species.traits.producesNectar else { return }
        #expect(species.traits.sugarYield == 0)
        #expect(species.traits.nectarAccessibility == 0)
    }
}
