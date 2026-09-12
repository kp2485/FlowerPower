//
//  DecisionViews.swift
//  FlowerPower
//
//  The decisions, in the app.
//
//  Each of these mirrors a notification's action buttons for a player who
//  opened the app instead. They are cards on the dashboard rather than
//  interruptions: the notification did the interrupting, and here the
//  decision simply waits with the reasons laid out beside it.
//

import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

// MARK: - A siege

struct ThreatDecisionCard: View {

    let threat: ActiveThreat
    let snapshot: ColonySnapshot
    @Environment(GameStore.self) private var store

    /// Answering a decision is the one thing on this screen the player
    /// actually does, so it gets a tap. Counted rather than flagged so a
    /// second answer feels like one too.
    @State private var answers = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: Theme.symbol(for: threat.predator))
                    .foregroundStyle(Theme.alarm)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(threat.predator.displayName) at the nest")
                        .font(.headline)
                    Text(threat.style.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(remaining)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Text(explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if snapshot.posture != .instinct {
                Label("Holding: \(snapshot.posture.displayName)", systemImage: "checkmark.shield.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.healthy)
            } else {
                VStack(spacing: 8) {
                    ForEach(threat.options.filter { $0 != .instinct }, id: \.self) { posture in
                        Button {
                            store.respond(to: threat, with: posture)
                            answers += 1
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(posture.displayName).font(.subheadline.weight(.semibold))
                                Text(posture.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.honey)
                    }
                }
                Text("Or let instinct handle it, which is what happens if you do nothing.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .card()
        .sensoryFeedback(.success, trigger: answers)
    }

    private var remaining: String {
        let days = threat.daysRemaining(on: snapshot.day)
        return days <= 0 ? "resolves today" : "\(days) day\(days == 1 ? "" : "s") to decide"
    }

    /// The engine owns this now, as `AttackStyle.explanation` — and it gained
    /// something in the move. The two styles with no posture to offer used to
    /// return the empty string, so a card could show a siege and then say
    /// nothing at all about it. They now say that there is nothing to be done,
    /// which is a better thing for a player to read than a blank.
    private var explanation: String { threat.style.explanation }
}

// MARK: - A swarm gathering

struct SwarmDecisionCard: View {

    let swarm: PendingSwarm
    let snapshot: ColonySnapshot
    @Environment(GameStore.self) private var store
    @State private var isRelocating = false
    @State private var answers = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(Theme.caution)
                    .accessibilityHidden(true)
                Text("The colony is preparing to swarm")
                    .font(.headline)
                Spacer()
                Text("\(swarm.daysRemaining(on: snapshot.day)) days")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Text("Swarm cells are started. The old queen will leave with most of the flying bees, and what stays will rest on a virgin queen's mating flight. This is how colonies reproduce — and how most of them end.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if swarm.discouraged {
                Label("Making room. It may still go.", systemImage: "hammer.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.healthy)
            } else {
                // Space first. It is what a beekeeper actually does about
                // congestion, and the only answer here that does not cost the
                // colony bees.
                // None of these is styled as the recommendation, deliberately.
                // Measured over 200 colonies, making room is worth more than
                // either of the others and more than any of them is worth
                // against simply letting the swarm go — so an interface that
                // pushed one of them forward would be pushing the wrong one.
                // They are alternatives with different costs, and the card
                // says what each costs.
                if snapshot.canAddComb, snapshot.canAffordComb {
                    Button {
                        store.addComb()
                        answers += 1
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open the Nest Up").font(.subheadline.weight(.semibold))
                            Text("\(snapshot.combOnOffer) cells of drawn comb, paid for in the honey it takes to make the wax. Room they can use today rather than room they cannot afford to fill.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.honey)
                } else if snapshot.canAddComb {
                    Label(
                        "There is room to open the nest up, but not the honey to draw comb into it — wax costs about seven times its weight in stores.",
                        systemImage: "drop.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if snapshot.canSplit {
                    Button {
                        store.splitColony()
                        answers += 1
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Divide Them Yourself").font(.subheadline.weight(.semibold))
                            Text("Move the queen and the house bees out now. Fewer go than would leave in a swarm, and the foragers stay with the nest because they know where it is.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.honey)
                } else if let days = snapshot.daysUntilSplitPossible {
                    // Said rather than shown as a dead button. A colony is
                    // divided onto a queen cell, and one that has only just
                    // started cups has nothing to leave behind.
                    Label(
                        days == 1
                            ? "You could divide them yourself tomorrow, once a queen cell is far enough along to leave behind."
                            : "You could divide them yourself in \(days) days, once a queen cell is far enough along to leave behind.",
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    store.discourageSwarm()
                    answers += 1
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Make Room").font(.subheadline.weight(.semibold))
                        Text(HivePosture.makeRoom.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(Theme.honey)

                Button {
                    isRelocating = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Move to a Larger Cavity").font(.subheadline.weight(.semibold))
                        Text("Abscond to somewhere roomier. The bees go; the comb, stores and brood do not.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(Theme.honey)

                Text("Or let them go, which is what happens if you do nothing.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .card()
        .sensoryFeedback(.success, trigger: answers)
        .sheet(isPresented: $isRelocating) {
            NewColonyView(reason: .relocating) { site in
                store.relocateHive(to: HiveLocation(coordinate: snapshot.nest.coordinate, type: site))
                isRelocating = false
            }
        }
    }

}

// MARK: - A swarm has left

struct DepartedSwarmCard: View {

    let swarm: DepartedSwarmSummary
    @Environment(GameStore.self) private var store
    @State private var isChoosingSite = false
    @State private var isGifting = false
    @State private var answers = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bird.fill")
                    .foregroundStyle(Theme.queen)
                    .accessibilityHidden(true)
                Text("A swarm has left")
                    .font(.headline)
            }

            Text("\(swarm.queenTitle) has gone with \(swarm.beeCount) bees and \(Int(swarm.honeyCarried.rounded())) units of honey in their crops. The colony that stays rests on a virgin queen. You can stay with it, or go with the swarm to a new site — your garden comes either way.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                isChoosingSite = true
            } label: {
                Label("Follow the Swarm", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.honey)

            HStack {
                Button("Stay With the Colony") {
                    store.letSwarmGo()
                    answers += 1
                }
                .buttonStyle(.bordered)
                Button("Give the Swarm Away") { isGifting = true }
                    .buttonStyle(.bordered)
            }
            .tint(Theme.honey)
        }
        .card()
        .sensoryFeedback(.success, trigger: answers)
        .sheet(isPresented: $isChoosingSite) {
            NewColonyView(reason: .firstColony) { site in
                store.followSwarm(to: HiveLocation(type: site))
                answers += 1
                isChoosingSite = false
            }
        }
        .sheet(isPresented: $isGifting) {
            ShareSwarmView()
        }
    }
}

// MARK: - The autumn entrance

struct EntranceDecisionCard: View {

    let snapshot: ColonySnapshot
    @Environment(GameStore.self) private var store
    @State private var answers = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "door.left.hand.closed")
                    .foregroundStyle(Theme.propolis)
                    .accessibilityHidden(true)
                Text("Autumn: the entrance")
                    .font(.headline)
            }

            Text("The bees will narrow the entrance with propolis before winter unless you say otherwise. Sealed, it keeps mice out and warmth in, and the damp with it. Open, the cluster breathes and anything small can walk in.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Seal It") {
                    store.decideEntrance(sealed: true)
                    answers += 1
                }
                .buttonStyle(.borderedProminent)
                Button("Keep It Open") {
                    store.decideEntrance(sealed: false)
                    answers += 1
                }
                .buttonStyle(.bordered)
            }
            .tint(Theme.honey)
        }
        .card()
        .sensoryFeedback(.success, trigger: answers)
    }
}

// MARK: - Honey

struct HoneyDecisionCard: View {

    let snapshot: ColonySnapshot
    @Environment(GameStore.self) private var store
    @State private var amount: Double = 0
    @State private var harvests = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "drop.fill")
                    .foregroundStyle(Theme.honey)
                    .accessibilityHidden(true)
                Text("The colony's surplus").font(.headline)
                Spacer()
                Text("\(Int(snapshot.honeyTaken.rounded())) taken so far")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)

            Text("What the bees have put away beyond what they need for winter. Every unit taken is a unit they do not have if the spring is late — the cap is what they can spare, and it moves with the season.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if snapshot.harvestableHoney < 1 {
                Text("Nothing to spare right now.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Slider(value: $amount, in: 0...snapshot.harvestableHoney, step: 1)
                    .tint(Theme.honey)
                    .accessibilityLabel("Honey to take")
                    .accessibilityValue("\(Int(amount)) of \(Int(snapshot.harvestableHoney)) units")
                HStack {
                    Text("\(Int(amount)) of \(Int(snapshot.harvestableHoney)) units")
                        .font(.caption.monospacedDigit())
                        .minimumScaleFactor(0.7)
                    Spacer()
                    Button("Take") {
                        store.takeHoney(amount)
                        amount = 0
                        harvests += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.honey)
                    .disabled(amount < 1)
                }
            }
        }
        .card()
        .sensoryFeedback(.success, trigger: harvests)
    }
}

// MARK: - Giving it back

/// The harvest run backwards, and the only decision in the game that spends
/// the score.
///
/// Everything shown here is the engine's arithmetic, not this view's: how
/// short they are, how much of the bank would actually fit in the comb, and
/// whether the question is open at all. A card that works out its own numbers
/// is a card that is quietly wrong in November.
struct FeedDecisionCard: View {

    let snapshot: ColonySnapshot
    @Environment(GameStore.self) private var store
    @State private var amount: Double = 0
    @State private var feeds = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "takeoutbag.and.cup.and.straw.fill")
                    .foregroundStyle(Theme.honey)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("They are short for winter").font(.headline)
                    Text(String(format: "%.0f units short", snapshot.storesShortfall))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.7)
                }
                Spacer()
                Text("\(Int(snapshot.honeyTaken.rounded())) banked")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)

            Text("Honey you took is still yours to give back, and a colony that goes into winter short of what it needs does not come out of it. What goes in is honey like any other: they will eat it, and burn it keeping warm.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if snapshot.feedOnOffer < 1 {
                Text("There is no room in the comb for any of it.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Slider(value: $amount, in: 0...snapshot.feedOnOffer, step: 1)
                    .tint(Theme.honey)
                    .accessibilityLabel("Honey to give back")
                    .accessibilityValue("\(Int(amount)) of \(Int(snapshot.feedOnOffer)) units")
                HStack {
                    Text("\(Int(amount)) of \(Int(snapshot.feedOnOffer)) units")
                        .font(.caption.monospacedDigit())
                        .minimumScaleFactor(0.7)
                    Spacer()
                    Button(DecisionAction.feed.title) {
                        store.feed(amount)
                        amount = 0
                        feeds += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.honey)
                    .disabled(amount < 1)
                }
                Text("Or leave them to it, which is what happens if you do nothing.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .card()
        .sensoryFeedback(.success, trigger: feeds)
        .onAppear {
            // Opens at what they are actually short of — the amount the
            // notification's one button would give — so the common case is a
            // single tap and the slider is for disagreeing with it.
            amount = min(snapshot.storesShortfall, snapshot.feedOnOffer).rounded()
        }
    }
}
