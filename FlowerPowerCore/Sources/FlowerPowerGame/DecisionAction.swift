//
//  DecisionAction.swift
//  FlowerPowerGame
//
//  An answer to a decision, as one vocabulary both ends of the game speak.
//
//  The design rule is that every decision is decidable from the lock screen or
//  a tap on the watch. That means the same handful of answers arrive from three
//  different places — a notification action button, a button on the watch, and
//  a card in the app — and until now only the first of those knew how to spell
//  them. The identifiers lived in `NotificationActions`, inside the Xcode
//  target, along with the switch that turned one into a change to the colony.
//  Nothing outside that file could answer a decision, and nothing outside a
//  Mac could compile the switch that did it.
//
//  So the vocabulary lives here instead. The identifier strings are exactly the
//  ones the notification categories were registered with, because a
//  notification sitting on somebody's lock screen from before the update will
//  come back with the old spelling and must still work.
//
//  What arrives here is the player's own choice on their own device, so it is
//  not treated as untrusted. What it is treated as is possibly *stale*: a
//  notification can sit on the lock screen for hours, and a watch can queue a
//  tap until it next sees the phone. By the time either arrives the siege may
//  be over. `GameStore.apply(_:)` checks the decision is still open and does
//  nothing rather than something wrong if it is not.
//

import Foundation
import FlowerPowerCore

public enum DecisionAction: Codable, Equatable, Sendable, Hashable {

    /// Answer a siege with a stance. `instinct` is a legitimate answer: it is
    /// what happens anyway, and saying so closes the decision.
    case posture(HivePosture)

    /// Try to talk the colony out of swarming.
    case discourageSwarm

    /// Open the nest up: more room, drawn now, paid for in honey.
    case addComb

    /// Divide the colony deliberately, before it divides itself.
    case split

    /// Let a gathering swarm go — which is to say, do nothing, on purpose.
    case letSwarmGo

    /// Stay with the colony after a swarm has already left, rather than
    /// following it.
    case staySwarm

    case sealEntrance
    case openEntrance

    /// Give banked honey back to a colony that is short for winter.
    ///
    /// Carries no amount, because from a lock screen or a watch face there is
    /// only one amount it could mean: what they are short of. Giving more
    /// would spend the player's score on honey the colony does not need, and
    /// giving less would leave the decision half-answered with no way to say
    /// so. `FeedDecisionCard` is where an amount can be chosen.
    case feed

    /// Send a tenth of the foragers to look at the country, for three days.
    ///
    /// The one decision the world adds, and the only one the game ever offers
    /// while things are going *well*: it is available during a flow, because a
    /// flow is when a colony can spare them. Carries nothing, because there is
    /// nothing to choose — the party goes to the ring of rumoured ground and
    /// comes back with all of it.
    case scout

    /// Following a swarm is deliberately absent. It needs a site chosen, and a
    /// site cannot be chosen from a notification or a watch face, so that one
    /// opens the app. See `NotificationActions.Action.followSwarm`.

    // MARK: - Identifiers

    /// Postures carry themselves in the suffix, so one handler serves every
    /// threat category.
    private static let posturePrefix = "posture."

    /// The wire spelling. Stable: these strings are registered with the
    /// notification centre and come back from the system, and an outstanding
    /// notification outlives an app update.
    public var identifier: String {
        switch self {
        case .posture(let posture): return Self.posturePrefix + posture.rawValue
        case .discourageSwarm: return "swarm.discourage"
        case .addComb: return "nest.addComb"
        case .split: return "swarm.split"
        case .letSwarmGo: return "swarm.let"
        case .staySwarm: return "swarm.stay"
        case .sealEntrance: return "entrance.seal"
        case .openEntrance: return "entrance.open"
        case .feed: return "colony.feed"
        case .scout: return "colony.scout"
        }
    }

    /// Nil for anything this version does not know, which includes the
    /// actions that need the app — and includes whatever a future version
    /// might send a watch that has not been updated yet.
    public init?(identifier: String) {
        if identifier.hasPrefix(Self.posturePrefix) {
            let suffix = String(identifier.dropFirst(Self.posturePrefix.count))
            guard let posture = HivePosture(rawValue: suffix) else { return nil }
            self = .posture(posture)
            return
        }

        switch identifier {
        case "swarm.discourage": self = .discourageSwarm
        case "nest.addComb": self = .addComb
        case "swarm.split": self = .split
        case "swarm.let": self = .letSwarmGo
        case "swarm.stay": self = .staySwarm
        case "entrance.seal": self = .sealEntrance
        case "entrance.open": self = .openEntrance
        case "colony.feed": self = .feed
        case "colony.scout": self = .scout
        default: return nil
        }
    }

    /// The button label. The same words on the lock screen, on the watch and
    /// in the app, which is the whole point of them living in one place.
    public var title: String {
        switch self {
        case .posture(let posture): return posture.displayName
        case .discourageSwarm: return "Make Room"
        case .addComb: return "Open the Nest Up"
        case .split: return "Divide Them"
        case .letSwarmGo: return "Let Them Go"
        case .staySwarm: return "Stay"
        case .sealEntrance: return "Seal It"
        case .openEntrance: return "Keep It Open"
        case .feed: return "Feed Them"
        case .scout: return "Send Scouts"
        }
    }

    /// The answers a gathering swarm is offered from a lock screen, in the
    /// order the measurement ranks them: making room first, letting them go
    /// last.
    ///
    /// Opening the nest up is among them only on its cue — see
    /// `ColonySnapshot.addCombIsOnCue` and `swarmOffersComb`. Taken when the
    /// nest is full it is worth two points of two-year survival; taken for
    /// the whole swarm window it costs four, and a notification category is
    /// registered once for all time, so the two cases are two categories.
    public static func swarmAnswers(offeringComb: Bool) -> [DecisionAction] {
        [.discourageSwarm] + (offeringComb ? [.addComb] : []) + [.split, .letSwarmGo]
    }

    /// Every answer there is, so a test can round-trip the lot.
    public static var all: [DecisionAction] {
        HivePosture.allCases.map(DecisionAction.posture) + [
            .discourageSwarm, .addComb, .split, .letSwarmGo,
            .staySwarm, .sealEntrance, .openEntrance, .feed, .scout
        ]
    }
}

public extension ColonySnapshot {

    /// Whether a gathering swarm should be offered "open the nest up": the
    /// cue, the room and the honey, all three. The watch asks the same three
    /// in `Simulation.decision(_:)`, which sits below this layer and cannot
    /// call it.
    var swarmOffersComb: Bool {
        addCombIsOnCue && canAddComb && canAffordComb
    }
}

// MARK: - Applying one

extension GameStore {

    /// Answers a decision, if it is still there to answer.
    ///
    /// - Returns: whether anything was done. False means the decision was
    ///   stale — the siege resolved, the swarm already gone, autumn over — and
    ///   the colony is untouched. A caller showing immediate feedback should
    ///   believe this rather than assume.
    ///
    /// Every case goes through the store's own player-action methods, so a
    /// decision answered from the lock screen takes exactly the path a button
    /// in the app takes, saving and republishing the snapshot with it. The
    /// staleness checks are the ones `NotificationActions` was making by hand;
    /// they are here now because the compiler can see this switch is
    /// exhaustive and could not see that one.
    @discardableResult
    public func apply(_ action: DecisionAction) -> Bool {
        switch action {
        case .posture(let posture):
            // The siege itself has to still be on. `respond(to:with:)` checks
            // the threat has not been replaced by a different one, which is
            // the case a stored identifier cannot detect.
            guard let threat = snapshot.activeThreat else { return false }
            respond(to: threat, with: posture)

        case .discourageSwarm:
            guard snapshot.pendingSwarm != nil else { return false }
            discourageSwarm()

        case .addComb:
            // Stale in the useful direction: if the swarm has already gone,
            // the room is still worth having, so this does not ask whether one
            // is pending. It asks only whether any comb was actually drawn —
            // a nest with nowhere to put it, or a colony that cannot afford
            // the wax, gets nothing and says so.
            guard addComb() > 0 else { return false }

        case .split:
            // This one is checked, and hard. A division taken after the colony
            // has already swarmed would send away a second half of a colony
            // that has just lost the first.
            guard snapshot.pendingSwarm != nil, snapshot.canSplit else { return false }
            guard splitColony() else { return false }

        case .letSwarmGo:
            // Doing nothing, on purpose. There is nothing to apply and nothing
            // to check: the answer is the absence of an answer, and the swarm
            // leaves or does not on its own terms. Reported as applied because
            // the decision *was* answered, which is what a caller wants to
            // know when it is deciding whether to stop asking.
            guard snapshot.pendingSwarm != nil else { return false }

        case .staySwarm:
            guard snapshot.departedSwarm != nil else { return false }
            letSwarmGo()

        case .feed:
            // Two ways to be stale, and both are ordinary rather than
            // exceptional: the colony may have provisioned itself since the
            // notification was posted, and the bank may have been emptied
            // into it from the card in the meantime. `feedOnOffer` also
            // covers the third case, which is a nest with no comb free to
            // put it in.
            guard snapshot.storesShortfall > 0, snapshot.feedOnOffer > 0 else { return false }
            guard feed(snapshot.storesShortfall) > 0 else { return false }

        case .scout:
            // Stale in the ordinary way: the flow may have ended while the
            // notification sat on the lock screen, or the foragers may have
            // found the last of the rumoured ground on their own. Both are
            // reasons to do nothing rather than to send a party after
            // something that is already on the map.
            guard snapshot.scoutDecisionOpen else { return false }
            guard sendScouts() else { return false }

        case .sealEntrance, .openEntrance:
            // Autumn only. Out of season there is nothing to decide: the bees
            // have clustered and nobody is doing any building, and recording a
            // choice in December would put a line in the almanac for something
            // that did not happen.
            guard snapshot.season == .autumn else { return false }
            decideEntrance(sealed: action == .sealEntrance)
        }

        return true
    }
}
