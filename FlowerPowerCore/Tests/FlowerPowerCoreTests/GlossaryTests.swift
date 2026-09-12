import Testing
@testable import FlowerPowerCore

/// The glossary, held to three things a glossary can quietly stop doing.
///
/// A term defined twice, an empty definition, or a cross-reference to a word
/// that is not in the book are all invisible from the outside — the screen
/// renders, it just says nothing useful or leads nowhere. The compiler already
/// covers the part it can: every enum-keyed definition comes out of an
/// exhaustive switch, so adding a posture or a predator fails the build rather
/// than shipping a word with no entry behind it.
@Suite("Glossary")
struct GlossaryTests {

    // MARK: - The book itself

    @Test("No word is defined twice")
    func termsAreUnique() {
        var seen = Set<String>()
        for entry in Glossary.all {
            let key = entry.term.lowercased()
            #expect(!seen.contains(key), "\(entry.term) is defined more than once")
            seen.insert(key)
        }
        #expect(seen.count == Glossary.all.count)
    }

    @Test("Every entry says something, and says it in sentences")
    func definitionsAreWritten() {
        for entry in Glossary.all {
            #expect(!entry.term.isEmpty)
            #expect(!entry.definition.isEmpty, "\(entry.term) has no definition")
            // One or two sentences. The floor catches a placeholder; the
            // ceiling catches an essay, which is what a glossary is not.
            #expect(
                entry.definition.count > 40,
                "\(entry.term) is defined in \(entry.definition.count) characters"
            )
            #expect(
                entry.definition.count < 600,
                "\(entry.term) has grown into an article"
            )
            #expect(
                entry.definition.hasSuffix(".") || entry.definition.hasSuffix("?"),
                "\(entry.term) is not written as a sentence"
            )
        }
    }

    @Test("Every cross-reference resolves to a real entry")
    func relatedTermsResolve() {
        for entry in Glossary.all {
            for name in entry.related {
                #expect(
                    Glossary.term(named: name) != nil,
                    "\(entry.term) points at '\(name)', which is not in the glossary"
                )
            }
            // And nothing points at itself, which is a dead end dressed up as
            // a link.
            #expect(
                !entry.related.contains { $0.lowercased() == entry.term.lowercased() },
                "\(entry.term) is related to itself"
            )
            #expect(
                Glossary.relatedTerms(of: entry).count == entry.related.count,
                "\(entry.term) lost a cross-reference in resolution"
            )
        }
    }

    @Test("The book is in alphabetical order")
    func sorted() {
        let names = Glossary.all.map { $0.term.lowercased() }
        #expect(names == names.sorted())
    }

    @Test("Lookup is case-insensitive, because nobody types capitals")
    func lookup() {
        #expect(Glossary.term(named: "supersedure")?.term == "Supersedure")
        #expect(Glossary.term(named: "SUPERSEDURE") != nil)
        #expect(Glossary.term(named: "Nectar Flow") != nil)
        #expect(Glossary.term(named: "haemolymph") == nil)
    }

    @Test("Search reads the definitions as well as the words")
    func search() {
        // "mite" is in no term's name and is the whole point of varroa.
        let mites = Glossary.search("mite")
        #expect(mites.contains { $0.term == "Varroa Mites" })

        #expect(Glossary.search("swarm").count >= 4)
        #expect(Glossary.search("").count == Glossary.all.count)
        #expect(Glossary.search("   ").count == Glossary.all.count)
        #expect(Glossary.search("nothing whatsoever").isEmpty)
    }

    @Test("Grouping by letter covers every entry exactly once")
    func grouping() {
        let groups = Glossary.grouped()
        let regrouped = groups.flatMap(\.terms)

        #expect(regrouped.count == Glossary.all.count)
        #expect(Set(regrouped.map(\.id)) == Set(Glossary.all.map(\.id)))
        #expect(groups.map(\.letter) == groups.map(\.letter).sorted())
        for group in groups {
            #expect(group.letter.count == 1)
            for entry in group.terms {
                #expect(entry.term.uppercased().hasPrefix(group.letter))
            }
        }
    }

    // MARK: - The engine's own vocabulary

    /// Every case of every keyed enum yields a definition, and that definition
    /// is in the book under the name the interface shows.
    ///
    /// The switches are exhaustive, so a new case is a build failure. What this
    /// adds is that the answer is not blank and is reachable by name — an
    /// exhaustive switch is perfectly happy to return "".
    @Test("Every engine word the interface shows has an entry")
    func everyEnumCaseIsDefined() {
        func check<T>(_ values: [T], _ term: (T) -> GlossaryTerm) {
            for value in values {
                let entry = term(value)
                #expect(!entry.definition.isEmpty, "\(value) has no definition")
                #expect(entry.definition.count > 40, "\(value) is barely defined")
                #expect(
                    Glossary.term(named: entry.term)?.definition == entry.definition,
                    "\(value) is defined as '\(entry.term)' but that is not in the glossary"
                )
            }
        }

        check(WorkerJob.allCases) { Glossary.term(for: $0) }
        check(HivePosture.allCases) { Glossary.term(for: $0) }
        check(Pathogen.allCases) { Glossary.term(for: $0) }
        check(Predator.allCases) { Glossary.term(for: $0) }
        check(Glossary.queenCellPurposes) { Glossary.term(for: $0) }
        check(DeathCause.allCases) { Glossary.term(for: $0) }
        check(HiveLocationType.allCases) { Glossary.term(for: $0) }
        check(ResourceKind.allCases) { Glossary.term(for: $0) }
    }

    /// The term for an enum case is the word the rest of the interface uses for
    /// it. If these ever drift apart, a player reading "Supersedure Cell" on
    /// one screen would find nothing under that name in the glossary.
    @Test("Enum entries are filed under their display names")
    func filedUnderDisplayNames() {
        #expect(Glossary.term(for: WorkerJob.nurseBee).term == WorkerJob.nurseBee.displayName)
        #expect(Glossary.term(for: HivePosture.makeRoom).term == "Make Room")
        #expect(Glossary.term(for: Pathogen.varroa).term == "Varroa Mites")
        #expect(Glossary.term(for: QueenCell.Purpose.emergency).term == "Emergency Cell")
        #expect(Glossary.term(for: DeathCause.swarmed).term == "Left with Swarm")
        #expect(Glossary.term(for: HiveLocationType.nestbox).term == "Nest Box")
        #expect(Glossary.term(for: ResourceKind.beeBread).term == "Bee Bread")
        #expect(Glossary.term(for: Predator.badger).term == "Honey Badger")
    }

    /// The words the game says to the player that are not enum cases. These are
    /// the ones there is no compiler check for, so they are listed here: a
    /// notification that says "supersedure" with nothing behind it is exactly
    /// the failure this file exists to prevent.
    @Test("The words with no enum behind them are in the book too", arguments: [
        "Swarm", "Afterswarm", "Supersedure", "Absconding", "Artificial Swarm",
        "Mating Flight", "Drone Layer", "Laying Workers", "Patriline",
        "Queen Pheromone", "Alarm Pheromone", "Hygienic Behaviour",
        "Winter Bees", "Winter Cluster", "Dearth", "Nectar Flow",
        "Propolis Envelope", "Corolla Depth", "Keystone Flower",
        "Drawn Comb", "Waggle Dance"
    ])
    func freeStandingTerms(name: String) {
        #expect(Glossary.term(named: name) != nil, "'\(name)' is not defined")
    }

    @Test("The whole vocabulary is accounted for")
    func size() {
        let expected = Glossary.freeStanding.count
            + WorkerJob.allCases.count
            + HivePosture.allCases.count
            + Pathogen.allCases.count
            + Predator.allCases.count
            + Glossary.queenCellPurposes.count
            + DeathCause.allCases.count
            + HiveLocationType.allCases.count
            + ResourceKind.allCases.count

        #expect(Glossary.all.count == expected)
    }
}
