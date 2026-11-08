import Testing
@testable import FlowerPowerCore

/// What the UX walkthrough of 2026-11-07 found in the engine's half of the
/// interface. See UX-WALKTHROUGH-2026-11-07.md at the repository root.
@Suite("UX walkthrough, 2026-11-07")
struct WalkthroughRegressionTests {

    /// Finding 3. In winter the headline said "short of stores" while the
    /// status, which only looked at stores in autumn, said "Steady".
    @Test("A colony short of winter stores is not called steady in winter")
    func winterShortfallIsStruggling() {
        var simulation = Fixture.thrivingSimulation(config: .standard, seed: 7_107)
        simulation.mutateWorld { world in
            let need = world.hive.winterStoresRequired
            world.hive.resources = ResourcePool()
            // Well clear of the laying floor, so the verdict is about the
            // winter rather than about starving today.
            world.hive.resources.add(max(need * 0.3, 20), of: .honey)
        }
        let hive = simulation.world.hive
        #expect(hive.isShortForWinter)
        #expect(ColonyStatus.evaluate(hive: hive, season: .winter, config: .standard) == .struggling)
    }

    @Test("A colony with its winter stores is not marked short")
    func winterReadyIsNotShort() {
        var simulation = Fixture.thrivingSimulation(config: .standard, seed: 7_108)
        simulation.mutateWorld { world in
            world.hive.resources.add(world.hive.winterStoresRequired * 2, of: .honey)
        }
        #expect(!simulation.world.hive.isShortForWinter)
    }

    /// Finding 6. The report kept no record of a disease going away, so its
    /// health card said only that it had appeared.
    @Test("The report records a cleared infection, and keeps it across a merge")
    func clearedInfectionsAreRecorded() {
        var first = CatchUpReport()
        first.record(.infectionDetected(.americanFoulbrood))
        first.record(.infectionCleared(.americanFoulbrood))
        #expect(first.clearedInfections == [.americanFoulbrood])

        var later = CatchUpReport()
        later.record(.infectionCleared(.varroa))
        #expect(first.merging(later).clearedInfections == [.americanFoulbrood, .varroa])
    }

    /// Finding 5. "The colony cleared american foulbrood."
    @Test("A disease named mid-sentence keeps its proper noun")
    func diseaseNameInSentence() {
        #expect(SimEvent.infectionCleared(.americanFoulbrood).narration
                == "The colony cleared American foulbrood.")
        #expect(SimEvent.infectionCleared(.varroa).narration == "The colony cleared varroa mites.")
    }

    /// Finding 4. The cave was "safe" and "cold" beside bars that drew it as
    /// the warmest site and a middling one to defend.
    @Test("The cave's description agrees with its numbers")
    func caveCopyMatchesNumbers() {
        let cave = HiveLocationType.cave
        #expect(cave.insulation >= HiveLocationType.livingTreeCavity.insulation)
        #expect(!cave.summary.localizedCaseInsensitiveContains("cold"))
        #expect(!cave.summary.localizedCaseInsensitiveContains("safe"))
    }
}

/// What playing on a phone found: identification stopped at a genus or family
/// and gave it in Latin, because the name list only names species.
@Suite("Names for genera and families")
struct TaxonNamingTests {

    private func species(_ family: String, _ genus: String, _ epithet: String, _ name: String = "") -> TaxonEmbeddingIndex.Entry {
        .init(rank: .species, family: family, genus: genus, epithet: epithet, commonName: name)
    }
    private func genus(_ family: String, _ genus: String) -> TaxonEmbeddingIndex.Entry {
        .init(rank: .genus, family: family, genus: genus, epithet: "", commonName: "")
    }
    private func family(_ family: String) -> TaxonEmbeddingIndex.Entry {
        .init(rank: .family, family: family, genus: "", epithet: "", commonName: "")
    }
    private func name(of genusName: String, in entries: [TaxonEmbeddingIndex.Entry]) -> String? {
        TaxonEmbeddingIndex.naming(entries).first { $0.rank == .genus && $0.genus == genusName }?.commonName
    }

    @Test("A genus takes the word most of its species share")
    func sharedHead() {
        let entries = [
            species("Rosaceae", "Rosa", "canina", "Dog rose"),
            species("Rosaceae", "Rosa", "arvensis", "Field rose"),
            species("Rosaceae", "Rosa", "rubiginosa", "Sweet-briar"),
            genus("Rosaceae", "Rosa")
        ]
        #expect(name(of: "Rosa", in: entries) == "Rose")
    }

    @Test("A vague last word keeps the word before it")
    func vagueHead() {
        let entries = [
            species("Aizoaceae", "Carpobrotus", "edulis", "Hottentot fig plant"),
            species("Aizoaceae", "Carpobrotus", "glaucescens", "Angular pigface plant"),
            species("Aizoaceae", "Carpobrotus", "chilensis", "Sea fig plant"),
            genus("Aizoaceae", "Carpobrotus")
        ]
        #expect(name(of: "Carpobrotus", in: entries) == "Fig plant")
    }

    @Test("A genus people call by its Latin name keeps it")
    func latinInUse() {
        let entries = [
            species("Ericaceae", "Rhododendron", "ponticum", "Common rhododendron"),
            species("Ericaceae", "Rhododendron", "luteum", "Yellow azalea"),
            species("Ericaceae", "Rhododendron", "molle", "Chinese azalea"),
            species("Ericaceae", "Rhododendron", "indicum", "Satsuki azalea"),
            genus("Ericaceae", "Rhododendron")
        ]
        #expect(name(of: "Rhododendron", in: entries) == "Rhododendron")
    }

    @Test("No shared word, or one name among many species, falls back to the Latin genus")
    func fallBackToLatin() {
        let entries = [
            species("Oleaceae", "Abeliophyllum", "distichum", "White forsythia"),
            species("Oleaceae", "Abeliophyllum", "other"),
            genus("Oleaceae", "Abeliophyllum"),
            genus("Acanthaceae", "Dicliptera")
        ]
        #expect(name(of: "Abeliophyllum", in: entries) == "Abeliophyllum")
        #expect(name(of: "Dicliptera", in: entries) == "Dicliptera")
    }

    @Test("A genus of one species takes that species' whole name")
    func monotypic() {
        let entries = [species("Araceae", "Pistia", "stratiotes", "water lettuce"), genus("Araceae", "Pistia")]
        #expect(name(of: "Pistia", in: entries) == "Water lettuce")
    }

    @Test("A word belongs to the genus that uses it most")
    func borrowedHead() {
        let entries = [
            species("Fagaceae", "Quercus", "robur", "English oak"),
            species("Fagaceae", "Quercus", "petraea", "Sessile oak"),
            species("Fagaceae", "Quercus", "rubra", "Red oak"),
            species("Proteaceae", "Helicia", "cochinchinensis", "Silky oak"),
            species("Proteaceae", "Helicia", "glabriflora", "Smooth oak"),
            genus("Fagaceae", "Quercus"),
            genus("Proteaceae", "Helicia")
        ]
        #expect(name(of: "Quercus", in: entries) == "Oak")
        #expect(name(of: "Helicia", in: entries) == "Helicia")
    }

    @Test("Names that are not English are dropped rather than shown")
    func foreignNamesDropped() {
        let named = TaxonEmbeddingIndex.naming([species("Asteraceae", "Taraxacum", "nordstedtii", "fläckmaskros")])
        #expect(named[0].commonName == "")
    }

    @Test("A family the game has notes on keeps its name; another is named for its type genus")
    func familyNames() {
        let named = TaxonEmbeddingIndex.naming([
            family("Rosaceae"), family("Gesneriaceae"), family("Zzzaceae"),
            genus("Gesneriaceae", "Gesneria"), genus("Gesneriaceae", "Streptocarpus")
        ])
        #expect(named[0].commonName == "Rose Family")
        #expect(named[1].commonName == "Gesneria Family")
        #expect(named[2].commonName == "")
    }

    @Test("A family placement with no notes is titled with the identifier's name for it")
    func genericFamilyTitle() {
        let taxon = Taxon(family: BotanicalFamily("Gesneriaceae"))
        #expect(FlowerSpecies.generic(for: taxon, commonName: "Gesneria Family").commonName == "Gesneria Family")
        #expect(FlowerSpecies.generic(for: taxon).commonName == "Gesneriaceae")
        #expect(FlowerSpecies.generic(for: Taxon(family: .rosaceae), commonName: "Something").commonName == "Rose Family")
    }
}
