import Testing
@testable import FlowerPowerCore

/// Every event has a sentence, and every sentence says something.
///
/// The narration used to live in the iOS target, where nothing on the
/// development machine could compile it, and it silently went non-exhaustive
/// when the engine gained the seven decision events. Exhaustiveness is now the
/// compiler's problem; what this suite adds is that each case produces prose
/// rather than an empty string, and that the cases carrying a number actually
/// put it in the sentence.
@Suite("Event narration")
struct EventNarrationTests {

    /// One instance of each case, in declaration order. If a case is added to
    /// `SimEvent` and not to this list, `everyCaseIsCovered` fails.
    static let everyCase: [SimEvent] = [
        .emerged(.worker),
        .died(.worker, .oldAge),
        .eggsLaid(count: 12, kind: .worker),

        .queenCellStarted(.swarm),
        .queenCellStarted(.supersedure),
        .queenCellStarted(.emergency),
        .queenEmerged(quality: 0.95),
        .queenEmerged(quality: 0.4),
        .queenMated(patrilines: 12),
        .matingFlightFailed,
        .queenLost,
        .queenFailing,
        .swarmed(beesLost: 400),
        .absconded(beesLost: 900),
        .supersededQueen,
        .layingWorkersAppeared,
        .colonyCollapsed,

        .cellsBuilt(count: 40, type: .worker),
        .combLost(count: 30),
        .patchDepleted(EntityID(rawValue: 1)),
        .patchOutOfBloom(EntityID(rawValue: 1)),
        .nectarFlowBegan,
        .dearth,

        .weatherChanged(.storm),
        .groundedByWeather,
        .overheating,
        .chilling,

        .infectionDetected(.varroa),
        .infectionCleared(.varroa),
        .infectionCritical(.varroa),

        .attacked(.wasp),
        .attackRepelled(.wasp),
        .raidSucceeded(.badger, storesLost: 45),

        .threatBegan(.hornet, resolvesOnDay: 210),
        .threatEnded(.hornet),
        .swarmPreparing(departsOnDay: 150),
        .swarmAbandoned,
        .postureAdopted(.holdEntrance),
        .postureAdopted(.instinct),
        .entranceSealed(true),
        .entranceSealed(false),
        .honeyTaken(18),

        .starving,
        .winterStoresLow(have: 40, need: 120)
    ]

    @Test("Every event narrates as a sentence")
    func everySentence() {
        for event in Self.everyCase {
            let sentence = event.narration
            #expect(!sentence.isEmpty, "\(event) narrates as nothing")
            #expect(sentence.hasSuffix("."), "\(event) narrates without a full stop")
        }
    }

    /// The seven cases the decision events added, which is where the missing
    /// narration actually was.
    @Test("The decision events narrate what they decided")
    func decisionEvents() {
        #expect(SimEvent.threatBegan(.hornet, resolvesOnDay: 210).narration.contains("210"))
        #expect(SimEvent.threatEnded(.hornet).narration.contains("Hornet"))
        #expect(SimEvent.swarmPreparing(departsOnDay: 150).narration.contains("150"))
        #expect(!SimEvent.swarmAbandoned.narration.isEmpty)
        #expect(SimEvent.honeyTaken(18).narration.contains("18"))

        // Sealing and leaving open must not read the same, which was the whole
        // point of asking.
        #expect(
            SimEvent.entranceSealed(true).narration
                != SimEvent.entranceSealed(false).narration
        )

        // Instinct is the unmarked state and should not be narrated as though
        // the colony had been ordered into it.
        let instinct = SimEvent.postureAdopted(.instinct).narration
        let held = SimEvent.postureAdopted(.holdEntrance).narration
        #expect(instinct != held)
        #expect(held.lowercased().contains("entrance"))
    }

    /// A highlight the player will actually be shown must be worth reading.
    @Test("Every highlight has something to say")
    func highlightsNarrate() {
        for event in Self.everyCase where event.isHighlight {
            #expect(event.narration.count > 10, "\(event) is shown but says little")
        }
    }
}
