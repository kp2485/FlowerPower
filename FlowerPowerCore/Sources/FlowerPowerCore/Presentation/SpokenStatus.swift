//
//  SpokenStatus.swift
//  FlowerPowerCore
//
//  The colony, out loud.
//
//  Siri reads this, so it is written for an ear rather than an eye, and that
//  rules out most of what the rest of the presentation layer does freely. A
//  gauge, a table and a percentage to one decimal place all become nothing at
//  all when spoken; "four thousand two hundred and eighteen bees" is a number
//  a listener cannot hold on to, and it claims a precision the answer does not
//  have anyway. So every number here is rounded to the coarseness the question
//  deserves, and there is not a `Double` anywhere in the output.
//
//  What it *says* is the same judgement `WatchSummary` makes for a glance —
//  the state, the season, what the bees are doing, and the one thing worth
//  doing about it — at the length a sentence read aloud can carry. It is in
//  the package for the usual reason: it reads a dozen facts off the engine
//  and orders a decision against them, and here that reasoning can be
//  compiled and tested rather than desk-checked.
//

import Foundation

extension ColonySnapshot {

    /// One to three sentences answering "how are my bees?".
    ///
    /// Built from the snapshot alone, so the same answer is available to Siri,
    /// to a Shortcut, and to anything else that has to say the colony's state
    /// without drawing it.
    public var spokenStatus: String {
        // A dead colony is owed the explanation and nothing else. Its
        // population is zero, its season is irrelevant and there is no
        // decision left to put to anybody, so every other sentence below
        // would be noise over the only fact the player came back for.
        guard status.isAlive else {
            return [
                "Your bees are gone.",
                epitaph,
                "A new swarm is looking for somewhere to live."
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        }

        var sentences = [
            "In \(season.displayName.lowercased()), the colony is "
                + "\(status.displayName.lowercased()), with \(spokenPopulation)."
        ]

        // The colony's own sentence about itself, unchanged. It is already
        // written for a glance, which is close enough to written for an ear,
        // and rewriting it here would mean two places to keep true.
        sentences.append(headline)

        if let next = spokenNextStep { sentences.append(next) }

        return sentences.joined(separator: " ")
    }

    /// The colony's size, at the precision a spoken answer can carry.
    var spokenPopulation: String {
        let count = population.total
        if count == 1 { return "one bee" }
        // Under a hundred is a colony in trouble, and the exact figure is the
        // interesting part — the difference between sixty bees and forty is
        // the difference between a cluster and an ending.
        if count < 100 { return "\(count) bees" }
        return "about \(Self.spokenRounding(of: count)) bees"
    }

    /// Rounds by magnitude, so the answer loses the digits it was never
    /// entitled to. Nearest ten in the hundreds, hundred in the thousands,
    /// thousand above that.
    static func spokenRounding(of count: Int) -> Int {
        let step: Int
        switch count {
        case ..<1_000: step = 10
        case ..<10_000: step = 100
        default: step = 1_000
        }
        return (count + step / 2) / step * step
    }

    /// The one thing worth doing, or nothing at all.
    ///
    /// Ordered by how long the window stays open rather than by how bad the
    /// news is, which is the order `ColonyNews` uses for the same reason: a
    /// siege resolves in a day or two, a swarm goes within the week, the
    /// entrance decision stands all autumn, and a faded garden waits for as
    /// long as the player lets it. A spoken answer has room for one of these,
    /// so it must be the one that will be gone first.
    var spokenNextStep: String? {
        if let threat = activeThreat {
            return "\(threat.predator.displayName) at the nest, \(spokenWindow(threat))."
        }

        if let departed = departedSwarm {
            return "A swarm has left with about \(Self.spokenRounding(of: departed.beeCount)) "
                + "bees. You can follow it or stay with the colony."
        }

        if let swarm = pendingSwarm, !swarm.discouraged {
            let days = swarm.daysRemaining(on: day)
            return "They are preparing to swarm"
                + (days > 0 ? " in about \(days) days" : " within the day")
                + ". Making room is the best answer there is."
        }

        // "Full" is the same test `ColonyNews` uses: the comb fills the cavity
        // *and* the cells in it are occupied. Either alone is ordinary. This
        // is the week before the swarm cells, and the last moment at which
        // room is cheaper than losing half the bees.
        if nest.combOccupancy >= 0.9, nest.builtCells >= nest.capacity {
            return canAddComb
                ? "The nest is full. Open it up and they will draw more comb; "
                    + "leave it and they will divide instead."
                : "The nest is full and there is no more cavity. Divide them "
                    + "before they divide themselves."
        }

        if entranceDecisionOpen {
            return "It is autumn, and the bees will seal the entrance for "
                + "winter unless you keep it open."
        }

        if let garden = spokenGardenStep { return garden }

        return nil
    }

    /// How long is left to answer a siege.
    private func spokenWindow(_ threat: ActiveThreat) -> String {
        switch threat.daysRemaining(on: day) {
        case 0: return "resolving today"
        case 1: return "with a day to answer"
        case let days: return "with \(days) days to answer"
        }
    }

    /// Nothing left to work, which is the one problem a player fixes by going
    /// outside — and so the one worth saying out loud.
    private var spokenGardenStep: String? {
        // Nothing blooms in winter and that is not the player's fault. Asking
        // them to go and photograph a flower in January is asking them to
        // fail.
        guard season != .winter else { return nil }

        // The headline already asks, in as many words, whenever the garden is
        // the colony's dominant problem — see `Simulation.headline`. A spoken
        // answer that asks twice in three sentences is worse than one that
        // asks once.
        guard !headline.contains("Photograph") else { return nil }

        if patches.isEmpty {
            return "They have no flowers at all. Photograph one to give them "
                + "something to work."
        }
        if !patches.contains(where: \.isInBloom) {
            return "Nothing you have found is in bloom. Photograph a fresh "
                + "flower."
        }
        return nil
    }
}
