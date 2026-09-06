//
//  EventNarration.swift
//  FlowerPowerCore
//
//  A sentence for every event, rather than an enum case.
//
//  This lived in `CatchUpReportView` in the iOS target, where nothing could
//  compile it. That is exactly why it was wrong: `SimEvent` gained seven cases
//  with the decision events — a siege beginning and ending, a swarm gathering
//  and being talked out of it, a posture adopted, the entrance decided, honey
//  taken — and the switch in the view was never extended to cover them. It had
//  been a non-exhaustive switch, which is to say a build failure, since the day
//  those cases were added.
//
//  Here the compiler checks it on every platform the package builds on, and
//  `EventNarrationTests` checks that each case actually says something. The
//  interface asks for `event.narration` and gets a sentence; that is the whole
//  contract.
//

import Foundation

extension SimEvent {

    /// A sentence a player can read.
    ///
    /// Written in the past tense throughout, because this is what gets shown in
    /// the catch-up report: an account of a stretch of time that has already
    /// happened. The two decision events that are still open when the player
    /// reads them — a siege begun, a swarm gathering — say so in a way that
    /// still reads as a report rather than a prompt, because the card and the
    /// notification are what actually ask.
    public var narration: String {
        switch self {

        // Population
        case .emerged(let kind):
            return "A \(kind.displayName.lowercased()) emerged."
        case .died(let kind, let cause):
            return "A \(kind.displayName.lowercased()) died of \(cause.displayName.lowercased())."
        case .eggsLaid(let count, let kind):
            return "The queen laid \(count) \(kind.displayName.lowercased()) eggs."

        // Colony lifecycle
        case .queenCellStarted(let purpose):
            switch purpose {
            case .swarm:
                return "The colony started swarm cells — it is preparing to divide."
            case .supersedure:
                return "The colony is quietly raising a replacement queen."
            case .emergency:
                return "Queenless — the colony is raising an emergency queen from young brood."
            }
        case .queenEmerged(let quality):
            return quality > 0.9
                ? "A new queen emerged, and a good one."
                : "A new queen emerged, though not a strong one."
        case .queenMated(let patrilines):
            return "The queen returned from her mating flight, mated with \(patrilines) drones."
        case .matingFlightFailed:
            return "The mating flight failed. The colony is in serious trouble."
        case .queenLost:
            return "The queen was lost."
        case .queenFailing:
            return "The queen is failing."
        case .swarmed(let lost):
            return "The colony swarmed. \(lost) bees left with the old queen."
        case .absconded(let lost):
            return "The colony absconded — all \(lost) bees abandoned the nest."
        case .supersededQueen:
            return "The old queen was replaced."
        case .layingWorkersAppeared:
            return "Laying workers have appeared. The colony cannot recover from this."
        case .colonyCollapsed:
            return "The colony has collapsed."

        // Economy
        case .cellsBuilt(let count, let type):
            return "\(count) \(type.displayName.lowercased())s were drawn."
        case .combLost(let count):
            return "\(count) cells of comb were lost."
        case .patchDepleted:
            return "A flower patch was worked out."
        case .patchOutOfBloom:
            return "A flower went out of season."
        case .nectarFlowBegan:
            return "A nectar flow started — the bees are bringing it in fast."
        case .dearth:
            return "A dearth. Little is coming in."

        // Environment
        case .weatherChanged(let sky):
            return "The weather turned \(sky.displayName.lowercased())."
        case .groundedByWeather:
            return "The bees were grounded by the weather."
        case .overheating:
            return "The brood nest overheated."
        case .chilling:
            return "The brood nest chilled."

        // Health
        case .infectionDetected(let pathogen):
            return "\(pathogen.displayName) appeared in the colony."
        case .infectionCleared(let pathogen):
            return "The colony cleared \(pathogen.displayName.lowercased())."
        case .infectionCritical(let pathogen):
            return "\(pathogen.displayName) has reached a critical level."

        // Defence
        case .attacked(let predator):
            return "\(predator.displayName) attacked the hive."
        case .attackRepelled(let predator):
            return "The guards drove off \(predator.displayName.lowercased())."
        case .raidSucceeded(let predator, let lost):
            return "\(predator.displayName) got in and took \(Int(lost)) of stores."

        // Decisions, and what the colony did about them
        case .threatBegan(let predator, let resolvesOnDay):
            return "\(predator.displayName) settled in to press the nest until "
                + "day \(resolvesOnDay)."
        case .threatEnded(let predator):
            return "\(predator.displayName) gave up on the nest."
        case .swarmPreparing(let departsOnDay):
            return "The colony began preparing to swarm, and will go about "
                + "day \(departsOnDay)."
        case .swarmAbandoned:
            return "The colony thought better of swarming and tore the cells down."
        case .postureAdopted(let posture):
            return posture == .instinct
                ? "The colony went back to doing what a colony does."
                : "The colony took up \(posture.displayName.lowercased())."
        case .entranceSealed(let sealed):
            return sealed
                ? "The entrance was propolised down to a slot for the winter."
                : "The entrance was left open for the winter."
        case .honeyTaken(let units):
            return "\(Int(units.rounded())) units of honey were taken."
        case .combAdded(let cells):
            return "The nest was opened up by \(cells) cells' worth of room."
        case .colonyDivided(let left):
            return "The colony was divided on purpose. \(left) bees went with "
                + "the old queen; the foragers stayed."

        // Warnings
        case .starving:
            return "The colony went hungry."
        case .winterStoresLow(let have, let need):
            return "Winter stores are short: \(Int(have)) of the \(Int(need)) needed."
        }
    }
}
