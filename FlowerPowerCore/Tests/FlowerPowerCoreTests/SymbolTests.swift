import Testing
@testable import FlowerPowerCore

/// Every engine type that the interface draws has a symbol and a word for each
/// of its cases, and the compiler checks it.
///
/// These were nine exhaustive switches in `Theme`, most of them repeated in
/// `WatchTheme` and `WidgetTheme` — three files in three targets, none of which
/// anything on this machine can compile. `SimEvent.narration` was the same
/// shape and had been a build failure for however long it took nobody to open
/// Xcode: the engine gained seven cases and the view did not.
///
/// The switches now live in the package, so adding a case fails the build here
/// instead. What these tests add on top is that each case says *something* —
/// an exhaustive switch is quite happy to return "".
@Suite("Interface vocabulary")
struct SymbolTests {

    /// `CaseIterable` types, checked wholesale.
    @Test("Every case of every drawn type has a symbol")
    func everythingHasASymbol() {
        func check<T: CaseIterable>(_ type: T.Type, _ symbol: (T) -> String) {
            for value in T.allCases {
                let name = symbol(value)
                #expect(!name.isEmpty, "\(type) case \(value) has no symbol")
                // SF Symbol names are lowercase words joined by dots; a stray
                // space is the usual way one gets typed wrong.
                #expect(!name.contains(" "), "\(type) case \(value) symbol '\(name)' has a space")
            }
        }

        check(Season.self) { $0.symbolName }
        check(Sky.self) { $0.symbolName }
        check(ResourceKind.self) { $0.symbolName }
        check(WorkerJob.self) { $0.symbolName }
        check(BeeKind.self) { $0.symbolName }
        check(DevelopmentStage.self) { $0.symbolName }
        check(Predator.self) { $0.symbolName }
        check(Pathogen.self) { $0.symbolName }
        check(ColonyStatus.self) { $0.symbolName }
        check(SimEvent.Severity.self) { $0.symbolName }
        check(HiveLocationType.self) { $0.symbolName }
        check(WatchDecision.Kind.self) { $0.symbolName }
    }

    /// The types that are not `CaseIterable`, listed by hand. If one gains a
    /// case the switch in `Symbols.swift` stops compiling, which is the real
    /// guard; this only checks they say something.
    @Test("The hand-listed types have symbols too")
    func handListedSymbols() {
        for style in [AttackStyle.entrance, .field, .comb, .pilfer, .catastrophic, .parasite] {
            #expect(!style.symbolName.isEmpty)
        }
        for kind in [AlmanacEntry.Kind.season, .forage, .queen, .swarm,
                     .threat, .disease, .stores, .harvest, .colony] {
            #expect(!kind.symbolName.isEmpty)
        }
        for purpose in [QueenCell.Purpose.swarm, .supersedure, .emergency] {
            #expect(!purpose.symbolName.isEmpty)
        }
    }

    // MARK: - Words

    /// Every site a swarm can settle in has to be describable, or the screen
    /// that asks the player to choose one is choosing for them.
    @Test("Every site can be described without reading the numbers")
    func everySiteHasASummary() {
        for site in HiveLocationType.allCases {
            #expect(!site.summary.isEmpty, "\(site) has no description")
            #expect(!site.displayName.isEmpty)
            #expect(site.summary.hasSuffix("."), "\(site) description is not a sentence")
            #expect(site.summary.count > 30, "\(site) description says nothing useful")
        }
    }

    /// Including the two styles there is no posture for. A card that shows a
    /// siege and then says nothing about it is worse than one that admits
    /// there is nothing to do.
    @Test("Every kind of attack is explained, including the hopeless ones")
    func everyAttackIsExplained() {
        for style in [AttackStyle.entrance, .field, .comb, .pilfer, .catastrophic, .parasite] {
            #expect(!style.explanation.isEmpty, "\(style) is not explained")
            #expect(style.explanation.hasSuffix("."))
        }

        #expect(AttackStyle.entrance.hasAnswer)
        #expect(AttackStyle.field.hasAnswer)
        #expect(AttackStyle.catastrophic.hasAnswer == false)
        #expect(AttackStyle.parasite.hasAnswer == false)
    }

    /// Every predator resolves to a style, so every predator is drawable and
    /// explainable without a case of its own. Twenty-three species, six ways in.
    @Test("Every predator is drawn and explained by how it attacks")
    func predatorsResolveToStyles() {
        for predator in Predator.allCases {
            #expect(predator.symbolName == predator.attackStyle.symbolName)
            #expect(!predator.displayName.isEmpty)
        }
        #expect(Predator.allCases.count > 20, "the roster shrank unexpectedly")
    }
}
