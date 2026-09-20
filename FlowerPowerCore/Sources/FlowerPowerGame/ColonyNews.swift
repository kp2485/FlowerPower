//
//  ColonyNews.swift
//  FlowerPowerGame
//
//  Deciding whether something is worth interrupting a person for.
//
//  This is the whole of the judgement behind a notification, kept apart from
//  the delivering of one so it can be tested. Getting it wrong is not a small
//  thing: an idle game that pings about nothing gets its notifications turned
//  off within a week, and after that it cannot say the one thing that actually
//  matters, which is that the colony is about to die.
//
//  Two rules do most of the work. Only tell someone about a *change*, because
//  a colony that has been struggling for a fortnight is not news every six
//  hours. And only ever on the way down, because nobody needs waking to hear
//  that things are fine.
//

import Foundation
import FlowerPowerCore

public struct ColonyNews: Equatable, Sendable {

    /// Stable per kind of news, so the system replaces an outstanding
    /// notification of the same kind rather than stacking another beside it.
    public let identifier: String
    public let title: String
    public let body: String

    public init(identifier: String, title: String, body: String) {
        self.identifier = identifier
        self.title = title
        self.body = body
    }

    /// The handful of things the decision actually turns on.
    ///
    /// A separate type rather than passing whole snapshots, for one practical
    /// reason: a test needs to put the colony in an exact state — thriving to
    /// steady, struggling to critical — and reaching those reliably by running
    /// a simulation is luck rather than testing. Written against these, every
    /// case can be stated directly.
    public struct Facts: Equatable, Sendable {

        public let status: ColonyStatus
        public let headline: String
        /// What ended the colony, when it has.
        public let epitaph: String?
        /// The most pressing critical alert, if there is one.
        public let criticalAlert: ColonyAlert?
        public let patchCount: Int
        public let patchesInBloom: Int

        // Decisions in front of the player.
        public var threat: ActiveThreat? = nil
        public var pendingSwarm: PendingSwarm? = nil
        public var departedSwarmDay: Int? = nil
        public var entranceDecisionOpen: Bool = false
        public var day: Int = 0

        /// The comb has filled the cavity and the colony has nowhere left to
        /// put anything. This is the state that produces swarm cells a week
        /// later, and it is the last moment at which giving room is cheaper
        /// than losing half the bees.
        public var nestIsFull: Bool = false
        /// Whether the site has any more room to give.
        public var canAddComb: Bool = false

        /// The colony is short of what it needs to overwinter and there is
        /// honey banked to give it. `Simulation.feedDecisionOpen`.
        public var feedDecisionOpen: Bool = false
        /// How far short, so the news can say the number.
        public var storesShortfall: Double = 0

        /// A flow is on, there is ground nobody has been to, and nobody is
        /// already out looking at it. `Simulation.scoutDecisionOpen`.
        public var scoutDecisionOpen: Bool = false
        /// How many stretches of country the dancers are pointing at, so the
        /// news can say the number.
        public var rumouredChunks: Int = 0

        /// Whether `headline` is one of the sentences about forage rather
        /// than about the colony. `ColonySnapshot.headlineIsAboutForage`.
        public var headlineIsAboutForage: Bool = false

        public init(
            status: ColonyStatus,
            headline: String = "",
            epitaph: String? = nil,
            criticalAlert: ColonyAlert? = nil,
            patchCount: Int = 0,
            patchesInBloom: Int = 0,
            threat: ActiveThreat? = nil,
            pendingSwarm: PendingSwarm? = nil,
            departedSwarmDay: Int? = nil,
            entranceDecisionOpen: Bool = false,
            day: Int = 0,
            nestIsFull: Bool = false,
            canAddComb: Bool = false,
            feedDecisionOpen: Bool = false,
            storesShortfall: Double = 0,
            scoutDecisionOpen: Bool = false,
            rumouredChunks: Int = 0
        ) {
            self.status = status
            self.headline = headline
            self.epitaph = epitaph
            self.criticalAlert = criticalAlert
            self.patchCount = patchCount
            self.patchesInBloom = patchesInBloom
            self.threat = threat
            self.pendingSwarm = pendingSwarm
            self.departedSwarmDay = departedSwarmDay
            self.entranceDecisionOpen = entranceDecisionOpen
            self.day = day
            self.nestIsFull = nestIsFull
            self.canAddComb = canAddComb
            self.feedDecisionOpen = feedDecisionOpen
            self.storesShortfall = storesShortfall
            self.scoutDecisionOpen = scoutDecisionOpen
            self.rumouredChunks = rumouredChunks
        }
    }

    // MARK: - The decision

    public static func between(before: Facts, after: Facts) -> ColonyNews? {

        // A decision arriving is always worth an interruption, because it
        // has a window, and a window the player never heard about is a
        // decision made for them by silence.
        if let threat = after.threat, before.threat != threat {
            return ColonyNews(
                identifier: "threat-\(threat.predator.rawValue)-\(threat.beganOnDay)",
                title: "\(threat.predator.displayName) at the nest",
                body: "\(threat.style.displayName). The colony holds by instinct unless you say otherwise. "
                    + "\(threat.daysRemaining(on: after.day)) days to decide."
            )
        }
        if let swarm = after.pendingSwarm, before.pendingSwarm != swarm, !swarm.discouraged {
            return ColonyNews(
                identifier: "swarm-\(swarm.startedOnDay)",
                title: "The colony is preparing to swarm",
                body: "Swarm cells are started. They will divide in about "
                    + "\(swarm.daysRemaining(on: after.day)) days. "
                    + (after.canAddComb
                       ? "Room is the answer to congestion; a deliberate split "
                            + "is the other one."
                       : "A deliberate split costs fewer bees than letting "
                            + "them go.")
            )
        }
        // Before the cells, not after them. A colony that has filled its
        // cavity will raise swarm cells within the week, and by then the only
        // answers left are arguing with it and losing half the bees. This is
        // the one moment when space is still cheap, so it is worth saying
        // once — and only once, which is what the before/after comparison is
        // for.
        if after.nestIsFull, !before.nestIsFull, after.pendingSwarm == nil {
            return ColonyNews(
                identifier: "nest-full-\(after.day)",
                title: "The nest is full",
                body: after.canAddComb
                    ? "Every cell is drawn and the cavity is worked out. Open "
                        + "the nest up and they will keep building; leave it "
                        + "and they will divide instead."
                    : "Every cell is drawn and there is no more cavity. They "
                        + "will divide before long unless you divide them "
                        + "first."
            )
        }
        if let departed = after.departedSwarmDay, before.departedSwarmDay != departed {
            return ColonyNews(
                identifier: "departed-\(departed)",
                title: "A swarm has left",
                body: "The old queen has gone with most of the bees. Stay with the colony, or follow the swarm."
            )
        }
        // The colony is short for winter and the player is holding honey it
        // could have. Said when the window opens and not again, like the
        // entrance: the engine already warns weekly about short stores, and
        // this is the one part of that warning the player can answer from the
        // lock screen.
        if after.feedDecisionOpen, !before.feedDecisionOpen {
            return ColonyNews(
                identifier: "feed-\(after.day / Season.daysPerYear)",
                title: "The colony is short for winter",
                body: String(
                    format: "They are %.0f units short of what they need, and you have "
                        + "honey put by. Feeding them is the only thing left that helps.",
                    after.storesShortfall
                )
            )
        }
        // The one piece of good news the game ever interrupts anybody with,
        // and it is here rather than higher up because it can always wait.
        // Once a year, like the entrance and the feeding: a flow comes and
        // goes several times a summer, and a colony that rumours fresh ground
        // every fortnight would otherwise ping every fortnight.
        if after.scoutDecisionOpen, !before.scoutDecisionOpen, after.rumouredChunks > 0 {
            return ColonyNews(
                identifier: "scout-\(after.day / Season.daysPerYear)",
                title: "The nectar is flowing",
                body: "They can spare a few. The dancers are pointing at "
                    + "\(after.rumouredChunks) "
                    + (after.rumouredChunks == 1 ? "stretch" : "stretches")
                    + " of country nobody has been to, and scouts would bring "
                    + "back all of it."
            )
        }
        if after.entranceDecisionOpen, !before.entranceDecisionOpen {
            return ColonyNews(
                identifier: "entrance-\(after.day / Season.daysPerYear)",
                title: "Autumn at the hive",
                body: "The bees will seal the entrance for winter unless you keep it open."
            )
        }

        // The end. Worth saying once, whatever else is true, and said even
        // though nothing can be done about it — a player who is never told
        // simply finds a dead colony whenever they next happen to look.
        if after.status == .collapsed, before.status != .collapsed {
            return ColonyNews(
                identifier: "collapsed",
                title: "The colony is gone",
                body: after.epitaph ?? "A new swarm is looking for somewhere to live."
            )
        }

        // Nothing to say about a colony holding steady or recovering, and
        // nothing to say about a decline that lands somewhere comfortable.
        guard after.status < before.status, after.status <= .struggling else {
            return nil
        }

        // A named problem beats a general one, and carries a suggestion the
        // player can act on.
        if let alert = after.criticalAlert {
            return ColonyNews(
                identifier: "alert-\(alert.kind.rawValue)",
                title: alert.title,
                body: alert.suggestion ?? alert.detail
            )
        }

        // No specific alert, but worse than it was. A player who has never
        // photographed anything is told the one thing the game is about.
        if after.patchCount == 0 {
            return ColonyNews(
                identifier: "no-forage",
                title: "Nothing to work",
                body: "Your bees have no flowers at all. Photograph some."
            )
        }

        // Flowers going out of season, or going over, is *not* said here, and
        // used to be. Every flower does it every year; there is wild forage
        // in the country around the nest now; and the first player to live
        // with these notifications said that flowers going out of season was
        // the only thing they ever said. So when the headline is one of the
        // forage sentences, the news is the decline and not the garden — the
        // garden says its own piece on the dashboard.
        return ColonyNews(
            identifier: "status-\(after.status.rawValue)",
            title: "The colony is \(after.status.displayName.lowercased())",
            body: after.headlineIsAboutForage
                ? "It was \(before.status.displayName.lowercased()) when you last heard."
                : after.headline
        )
    }

    public static func between(
        before: ColonySnapshot,
        after: ColonySnapshot
    ) -> ColonyNews? {
        between(before: before.newsFacts, after: after.newsFacts)
    }
}

public extension ColonySnapshot {

    var newsFacts: ColonyNews.Facts {
        ColonyNews.Facts(
            status: status,
            headline: headline,
            epitaph: epitaph,
            criticalAlert: alerts.first { $0.severity == .critical },
            patchCount: patches.count,
            patchesInBloom: patches.filter(\.isInBloom).count,
            threat: activeThreat,
            pendingSwarm: pendingSwarm,
            departedSwarmDay: departedSwarm?.day,
            entranceDecisionOpen: entranceDecisionOpen,
            day: day,
            // "Full" means the comb fills the cavity *and* the cells in it are
            // occupied. Either alone is ordinary: a colony always has more
            // cavity than comb early on, and a colony always fills the comb it
            // has during a flow.
            nestIsFull: nest.combOccupancy >= 0.9 && nest.builtCells >= nest.capacity,
            canAddComb: canAddComb,
            feedDecisionOpen: feedDecisionOpen,
            storesShortfall: storesShortfall,
            scoutDecisionOpen: scoutDecisionOpen,
            rumouredChunks: terrain?.rumoured.count ?? 0
        )
        .with(headlineIsAboutForage: headlineIsAboutForage)
    }
}

extension ColonyNews.Facts {

    /// Set apart from the initialiser, which a dozen tests call by label and
    /// which has no need of another parameter.
    func with(headlineIsAboutForage: Bool) -> ColonyNews.Facts {
        var copy = self
        copy.headlineIsAboutForage = headlineIsAboutForage
        return copy
    }
}
