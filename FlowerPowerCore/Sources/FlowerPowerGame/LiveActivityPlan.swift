//
//  LiveActivityPlan.swift
//  FlowerPowerGame
//
//  Which Live Activities should be on the lock screen right now, and for how
//  much longer.
//
//  This judgement used to live in the app, next to ActivityKit, and it had one
//  rule: a card is up for as long as the thing it is about is happening. That
//  sounds right and is wrong for this game, because the game's clock is slow.
//  A skunk works a nest for three simulated days, which is six real hours, and
//  a swarm gathers for eight, which is most of a real day — and the card sat
//  on the lock screen and in the Dynamic Island for all of it, then for up to
//  four hours more, because that is what iOS does with an activity ended
//  under the default dismissal policy. The first player to see one said it
//  stayed "way too long", and it had.
//
//  The fix was to keep a card only while there was something to decide, and
//  never for more than a simulated day. The same player then said the other
//  half: "If it is going to be live for 2 hours, it needs to be more
//  engaging." Two hours of one sentence is not a Live Activity. So a card now
//  has three phases, and each of them is doing something:
//
//  - **Deciding.** The question is open and the answers are on the card, one
//    button per answer, in the order the notification offers them. A clock
//    counts down to the moment instinct answers for the player. Never longer
//    than a simulated day from the event's start, which is about two real
//    hours — nobody is punished for being at work, and a question unanswered
//    after that has been answered by not answering, so the card goes.
//  - **Holding.** The player has answered. The buttons go, and the card
//    shows what the colony is doing in the posture they chose — guards massed
//    at the entrance — with a clock to the moment it is settled. This one
//    stays up until the event resolves, because the player chose it and the
//    clock is live; but never past ActivityKit's eight hours.
//  - **Resolved.** The event is over, and the card says how: driven off or
//    not, what it cost, whether the swarm went. It is readable for half an
//    hour and then gone. The old card simply vanished, which left the player
//    to open the app to find out whether the skunk had got in.
//
//  ActivityKit cannot redraw a card while the app is suspended, and there is
//  no push server. So everything on a card that changes over its life is a
//  real `Date` the widget counts towards by itself — `deadline` and
//  `resolvesAt` — and this plan is where those dates come from. It takes them
//  as a function from simulated day to real instant, so it never reads the
//  wall clock and the tests do not either.
//
//  It is here rather than in the app for the usual reason: this is a
//  judgement about engine state, and the package is where a judgement can be
//  tested without a phone.
//

import Foundation
import FlowerPowerCore

public struct LiveActivityPlan: Equatable, Sendable {

    /// The three things at the hive that have a duration.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case siege
        case swarm
        case matingFlight
    }

    /// Where a card is in its life. See the top of the file.
    public enum Phase: String, Codable, Sendable, CaseIterable {
        case deciding
        case holding
        case resolved
    }

    /// Which event a card is about.
    ///
    /// Carried by the card for its whole life — it goes in the activity's
    /// attributes, which never change — so that a card on the lock screen is
    /// matched with the plan by what it is *about* rather than by its kind. A
    /// skunk that leaves and a wasp that arrives inside one catch-up are two
    /// sieges, and the skunk's card has to say how the skunk went, not be
    /// quietly relabelled as the wasp's.
    public struct Event: Hashable, Sendable {
        public let kind: Kind
        /// The simulated day the siege began, the swarm cells were started or
        /// the queen emerged.
        public let startedOnDay: Int
        /// Who is at the nest, for a siege.
        public let predator: Predator?

        public init(kind: Kind, startedOnDay: Int, predator: Predator? = nil) {
            self.kind = kind
            self.startedOnDay = startedOnDay
            self.predator = predator
        }
    }

    /// What a card draws besides its words: the numbers that make it a scene.
    ///
    /// Every field is optional because each kind of event has its own, and the
    /// card draws whichever are there.
    public struct Scene: Equatable, Sendable {
        /// Bees on guard duty at the entrance.
        public var guards: Int?
        /// Alarm pheromone, 0...1.
        public var alarm: Double?
        /// Bees who died in the siege. Only known once it is settled: the
        /// engine resolves a siege in one stroke on its last day and records
        /// the cost then, so there is no running total to show while it goes
        /// on — and a number made up for the card would be the card lying.
        public var beesLost: Int?
        public var storesLost: Double?
        /// Whether the attacker was driven off.
        public var repelled: Bool?
        /// About how many bees are getting ready to leave with the swarm, or
        /// how many did.
        public var departing: Int?
        /// Queen cells in the comb.
        public var queenCells: Int?

        public init(
            guards: Int? = nil,
            alarm: Double? = nil,
            beesLost: Int? = nil,
            storesLost: Double? = nil,
            repelled: Bool? = nil,
            departing: Int? = nil,
            queenCells: Int? = nil
        ) {
            self.guards = guards
            self.alarm = alarm
            self.beesLost = beesLost
            self.storesLost = storesLost
            self.repelled = repelled
            self.departing = departing
            self.queenCells = queenCells
        }
    }

    public struct Item: Equatable, Sendable {
        public let event: Event
        public let phase: Phase
        public let title: String
        /// One line: what the colony is doing about it, or how it ended.
        public let status: String
        /// The colony's posture, for display.
        public let posture: String
        /// One button each, in the order the notification offers them. Empty
        /// outside `.deciding`, and empty for a siege nothing can be done
        /// about.
        public let answers: [DecisionAction]
        public let scene: Scene
        /// SF Symbol for the card.
        public let symbol: String
        /// When the event began, in real time. Where the ring starts filling.
        public let startedAt: Date
        /// When instinct answers for the player. The deciding card counts
        /// down to this; on a holding card it is the same as `resolvesAt`.
        public let deadline: Date
        /// When the siege or the swarm is settled, as near as the engine can
        /// say. The holding card counts down to this.
        public let resolvesAt: Date
        /// When the card has outstayed its welcome, whatever the event is
        /// still doing. The app makes it the activity's stale date.
        public let staleDate: Date

        public var kind: Kind { event.kind }

        /// Whether the player can still do something about it from the card.
        public var decisionOpen: Bool { phase == .deciding && !answers.isEmpty }
    }

    /// The longest a card stays in `.deciding`, in simulated days. One is
    /// about two real hours, and half that in a double-speed winter.
    public static let longestDays = 1

    /// ActivityKit ends any activity eight hours after it starts. A holding
    /// card is kept inside that, measured from the start of the day its event
    /// began — which is never later than the card itself began, so the cap
    /// can only err on the early side.
    public static let longestActivity: TimeInterval = 8 * 3600

    /// How long a resolved card stays readable before it is dismissed.
    public static let outcomeLingers: TimeInterval = 30 * 60

    public let items: [Item]

    /// - Parameters:
    ///   - now: the real instant the plan is for. Only the eight-hour cap on
    ///     a holding card reads it; everything else is by simulated day.
    ///   - swarmDepartureShare: the share of the adult workers a swarm takes,
    ///     for the estimate on the swarm card. `SimulationConfig`'s by
    ///     default; `init(simulation:now:)` passes the colony's own.
    ///   - dateOfDay: the real instant a simulated day begins, past or
    ///     future. See `date(ofDay:on:)`.
    public init(
        snapshot: ColonySnapshot,
        now: Date,
        swarmDepartureShare: Double = SimulationConfig().swarmDepartureShare,
        dateOfDay: (Int) -> Date
    ) {
        var items: [Item] = []
        let day = snapshot.day
        // The engine settles sieges and swarms at the turn of a day, so an
        // event whose day has come and which is still on will be settled at
        // the next one. The clock never counts down to a moment already gone.
        let nextTurn = dateOfDay(day + 1)

        // A siege. A siege with nothing to offer — a bear, a badger — still
        // gets its card for the day, because it is the most dramatic thing
        // that happens to a colony and the card is how the player hears about
        // it.
        if let threat = snapshot.activeThreat {
            let event = Event(kind: .siege, startedOnDay: threat.beganOnDay, predator: threat.predator)
            let startedAt = dateOfDay(threat.beganOnDay)
            let resolvesAt = max(dateOfDay(threat.resolvesOnDay), nextTurn)
            let offered = threat.options.filter { $0 != .instinct }
            let scene = Scene(
                guards: snapshot.population.jobs[.guardBee] ?? 0,
                alarm: snapshot.alarm
            )
            let title = "\(threat.predator.displayName) at the nest"

            // Answered means answered *with one of this siege's answers*. A
            // colony still making room from a swarm last week holds a posture
            // too, and that posture is no answer to a skunk.
            let answered = snapshot.posture != .instinct && offered.contains(snapshot.posture)

            if answered {
                let until = min(resolvesAt, startedAt.addingTimeInterval(Self.longestActivity))
                if now < until {
                    items.append(Item(
                        event: event,
                        phase: .holding,
                        title: title,
                        status: Self.underWay(snapshot.posture),
                        posture: snapshot.posture.displayName,
                        answers: [],
                        scene: scene,
                        symbol: threat.predator.symbolName,
                        startedAt: startedAt,
                        deadline: resolvesAt,
                        resolvesAt: resolvesAt,
                        staleDate: until
                    ))
                }
            } else if day < threat.beganOnDay + Self.longestDays {
                let deadline = min(dateOfDay(threat.beganOnDay + Self.longestDays), resolvesAt)
                items.append(Item(
                    event: event,
                    phase: .deciding,
                    title: title,
                    status: offered.isEmpty
                        ? "Nothing to be done but wait"
                        : "Choose how the colony meets it",
                    posture: snapshot.posture.displayName,
                    answers: offered.map(DecisionAction.posture),
                    scene: scene,
                    symbol: threat.predator.symbolName,
                    startedAt: startedAt,
                    deadline: deadline,
                    resolvesAt: resolvesAt,
                    staleDate: deadline
                ))
            }
        }

        // Swarm cells.
        if let swarm = snapshot.pendingSwarm {
            let event = Event(kind: .swarm, startedOnDay: swarm.startedOnDay)
            let startedAt = dateOfDay(swarm.startedOnDay)
            let resolvesAt = max(dateOfDay(swarm.departsOnDay), nextTurn)
            let scene = Scene(
                departing: Self.departing(snapshot, share: swarmDepartureShare),
                queenCells: snapshot.nest.queenCells.count
            )
            let title = "Preparing to swarm"

            if swarm.discouraged {
                // Made room for, one way or the other. Drawing comb sets the
                // same flag as making room but without the posture, so the
                // sentence says which.
                let until = min(resolvesAt, startedAt.addingTimeInterval(Self.longestActivity))
                if now < until {
                    items.append(Item(
                        event: event,
                        phase: .holding,
                        title: title,
                        status: snapshot.posture == .makeRoom
                            ? "Builders drawing comb, foragers held back. They may still go."
                            : "New comb drawn. They may still go.",
                        posture: snapshot.posture.displayName,
                        answers: [],
                        scene: scene,
                        symbol: "arrow.triangle.branch",
                        startedAt: startedAt,
                        deadline: resolvesAt,
                        resolvesAt: resolvesAt,
                        staleDate: until
                    ))
                }
            } else if day < swarm.startedOnDay + Self.longestDays {
                // In the measured order the notification uses: making room
                // first, then opening the nest up, then dividing. Each only
                // where the engine would honour it — a button that does
                // nothing is worse than no button. "Let them go" is not here,
                // for the reason instinct is not on a siege card: it is what
                // happens if nobody answers, and it changes nothing the card
                // could show, so it would be a button that appears not to
                // work.
                var answers: [DecisionAction] = [.discourageSwarm]
                if snapshot.canAddComb && snapshot.canAffordComb { answers.append(.addComb) }
                if snapshot.canSplit { answers.append(.split) }

                let deadline = min(dateOfDay(swarm.startedOnDay + Self.longestDays), resolvesAt)
                items.append(Item(
                    event: event,
                    phase: .deciding,
                    title: title,
                    status: "Swarm cells started",
                    posture: snapshot.posture.displayName,
                    answers: answers,
                    scene: scene,
                    symbol: "arrow.triangle.branch",
                    startedAt: startedAt,
                    deadline: deadline,
                    resolvesAt: resolvesAt,
                    staleDate: deadline
                ))
            }
        }

        // A virgin queen, on the day she emerges. There is nothing to decide,
        // and she may be a virgin for a week; the card is the announcement
        // and the dashboard carries the wait. Holding, in that nothing is
        // asked — but the card counts nothing down, because nobody can say
        // when she will fly.
        if snapshot.queen.state == .virgin, snapshot.queen.ageDays < Self.longestDays {
            let emerged = day - snapshot.queen.ageDays
            let expires = dateOfDay(emerged + Self.longestDays)
            items.append(Item(
                event: Event(kind: .matingFlight, startedOnDay: emerged),
                phase: .holding,
                title: "A virgin queen",
                status: "Waiting on her mating flight",
                posture: snapshot.posture.displayName,
                answers: [],
                scene: Scene(),
                symbol: "crown.fill",
                startedAt: dateOfDay(emerged),
                deadline: expires,
                resolvesAt: expires,
                staleDate: expires
            ))
        }

        self.items = items
    }

    public func item(_ kind: Kind) -> Item? {
        items.first { $0.kind == kind }
    }

    public func item(for event: Event) -> Item? {
        items.first { $0.event == event }
    }

    // MARK: - How it ended

    /// The last word on a card whose event is over, or nil if there is none
    /// to say.
    ///
    /// Nil in two different cases, and the caller treats them the same —
    /// takes the card down at once. The event may not be over: a deciding
    /// card left unanswered for its day comes down while the siege goes on,
    /// and there is no ending to tell yet. Or it may be over in a way that is
    /// not this card's to narrate — the colony moved, or died — which the
    /// app says far better than a lock-screen line could.
    ///
    /// - Parameter attacks: `World.attackHistory`. The snapshot keeps only
    ///   which predators came, not what they cost, and the cost is the point.
    public static func outcome(
        for event: Event,
        in snapshot: ColonySnapshot,
        attacks: [AttackRecord],
        now: Date
    ) -> Item? {
        guard snapshot.status.isAlive else { return nil }

        switch event.kind {
        case .siege:
            if let threat = snapshot.activeThreat,
               threat.beganOnDay == event.startedOnDay,
               threat.predator == event.predator {
                return nil
            }
            guard let predator = event.predator,
                  let record = attacks.last(where: {
                      $0.predator == predator && $0.day >= event.startedOnDay
                  })
            else { return nil }

            return resolved(
                event,
                title: record.wasRepelled
                    ? "\(predator.displayName) driven off"
                    : "\(predator.displayName) is gone",
                status: toll(record),
                scene: Scene(
                    beesLost: record.beesLost,
                    storesLost: record.storesLost,
                    repelled: record.wasRepelled
                ),
                symbol: predator.symbolName,
                snapshot: snapshot,
                now: now
            )

        case .swarm:
            if let swarm = snapshot.pendingSwarm, swarm.startedOnDay == event.startedOnDay {
                return nil
            }
            // Gone, whether they swarmed or the player divided them first:
            // the engine keeps both as the swarm that left, and both are the
            // colony dividing. What is left is a choice the card cannot
            // offer — following needs a site chosen — so it says where to
            // make it.
            if let departed = snapshot.departedSwarm, departed.day >= event.startedOnDay {
                return resolved(
                    event,
                    title: "The colony has divided",
                    status: "\(departed.queenTitle) left with \(plural(departed.beeCount, "bee")). Follow them or stay, in FlowerPower.",
                    scene: Scene(departing: departed.beeCount),
                    symbol: "arrow.triangle.branch",
                    snapshot: snapshot,
                    now: now
                )
            }
            return resolved(
                event,
                title: "The swarm is off",
                status: "They thought better of it. The swarm cells are down and the queen stays.",
                scene: Scene(queenCells: snapshot.nest.queenCells.count),
                symbol: "house.fill",
                snapshot: snapshot,
                now: now
            )

        case .matingFlight:
            // Her card is an announcement, and it has already been made.
            return nil
        }
    }

    // MARK: - Dates

    /// The real instant a simulated day begins, before or after now.
    ///
    /// `SimClock.date(atTick:)` only walks forward — a tick already processed
    /// comes back as the present — and a card needs the past too, for the
    /// start of the ring. So the past is walked back tick by tick at each
    /// tick's own length, winter's shorter ones included.
    public static func date(ofDay day: Int, on clock: SimClock) -> Date {
        let target = day * SimClock.ticksPerDay
        let present = clock.date(atTick: clock.tick)
        guard target < clock.tick else { return clock.date(atTick: target) }
        var seconds = 0.0
        for tick in target..<clock.tick {
            seconds += clock.seconds(forTick: tick)
        }
        return present.addingTimeInterval(-seconds)
    }

    // MARK: - Words

    /// What the colony is doing in the posture the player chose, as a scene
    /// rather than as the name of a button.
    static func underWay(_ posture: HivePosture) -> String {
        switch posture {
        case .holdEntrance: return "Guards massed at the entrance"
        case .narrowEntrance: return "The entrance propolised down to a slot"
        case .foragersHome: return "Foragers kept in, the flowers left alone"
        case .cleanersOut: return "Cleaners combing the nest for larvae"
        case .makeRoom: return "Builders drawing comb, foragers held back"
        case .instinct: return "The colony holds by instinct"
        }
    }

    /// What a settled siege cost, in one line.
    static func toll(_ record: AttackRecord) -> String {
        if record.wasRepelled {
            return record.beesLost == 0
                ? "Turned away without a bee lost"
                : "\(plural(record.beesLost, "defender")) died driving it off"
        }
        var losses: [String] = []
        if record.beesLost > 0 { losses.append("\(plural(record.beesLost, "bee")) lost") }
        let stores = Int(record.storesLost.rounded())
        if stores > 0 { losses.append("\(stores) honey taken") }
        if record.combLost > 0 { losses.append("\(plural(record.combLost, "cell")) of comb spoiled") }

        switch losses.count {
        case 0: return "It took nothing"
        case 1: return capitalised(losses[0])
        default:
            let head = losses.dropLast().joined(separator: ", ")
            return capitalised("\(head) and \(losses[losses.count - 1])")
        }
    }

    /// Roughly how many would go, by the engine's own share and ceiling. The
    /// colony's temperament moves it a little either way, and the snapshot
    /// does not carry that — so the card says "about".
    static func departing(_ snapshot: ColonySnapshot, share: Double) -> Int {
        let adultWorkers = max(0, snapshot.population.adults - snapshot.population.drones - 1)
        return Int((Double(adultWorkers) * min(0.8, share)).rounded())
    }

    private static func resolved(
        _ event: Event,
        title: String,
        status: String,
        scene: Scene,
        symbol: String,
        snapshot: ColonySnapshot,
        now: Date
    ) -> Item {
        Item(
            event: event,
            phase: .resolved,
            title: title,
            status: status,
            posture: snapshot.posture.displayName,
            answers: [],
            scene: scene,
            symbol: symbol,
            startedAt: now,
            deadline: now,
            resolvesAt: now,
            staleDate: now.addingTimeInterval(outcomeLingers)
        )
    }

    private static func plural(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }

    private static func capitalised(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}

// MARK: - From a simulation

extension LiveActivityPlan {

    /// The plan for a colony, with its dates from the colony's own clock.
    ///
    /// - Parameter snapshot: the simulation's snapshot, when the caller has
    ///   it already. A store always does, and taking another one is not free.
    public init(simulation: Simulation, now: Date, snapshot: ColonySnapshot? = nil) {
        let clock = simulation.clock
        self.init(
            snapshot: snapshot ?? simulation.snapshot(),
            now: now,
            swarmDepartureShare: simulation.config.swarmDepartureShare,
            dateOfDay: { LiveActivityPlan.date(ofDay: $0, on: clock) }
        )
    }
}
