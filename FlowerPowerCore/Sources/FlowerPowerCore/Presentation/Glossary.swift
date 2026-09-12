//
//  Glossary.swift
//  FlowerPowerCore
//
//  The words the game uses, explained.
//
//  This game says "supersedure" and "drone layer" and "dearth" to the player
//  and expects to be understood. Most of it is guessable from context and some
//  of it is not: nobody works out from a notification what a patriline is, or
//  why a colony full of drones cannot be saved, or why a flower a bumblebee
//  empties every morning yields these bees nothing.
//
//  Two rules shaped this file.
//
//  **Where the game does something with a concept, the definition says what.**
//  A glossary that only recited textbook definitions would be a worse version
//  of a search engine. The interesting half of each entry is the consequence:
//  queen pheromone thins as the colony grows, *which is why big colonies
//  swarm*; wax costs seven times its weight in honey, *which is why bees only
//  build on a flow*.
//
//  **Everything the engine has an enum for is keyed to that enum.** Thirty-odd
//  of these terms are the words on the game's own screens — the job a bee is
//  doing, the posture the player chose, what killed a bee, what the colony is
//  living in. Those come out of exhaustive switches, so adding a case to any of
//  them fails the build here rather than shipping a screen with a word on it
//  that nothing explains. It is the same reason `Symbols.swift` and
//  `EventNarration.swift` are in the package: `SimEvent.narration` was a switch
//  in a view nothing on the development machine compiles, and it had been a
//  build failure for months.
//
//  `GlossaryTests` checks the rest: that no term is defined twice, that none of
//  them is empty, and that every cross-reference resolves to a term that is
//  really here.
//

import Foundation

// MARK: - A term

public struct GlossaryTerm: Identifiable, Codable, Equatable, Sendable {

    /// The word itself, in the capitalisation the interface shows.
    public let term: String

    /// One or two sentences. Biologically correct, and where the game acts on
    /// the concept, what it does.
    public let definition: String

    /// Other terms worth reading next, by name. Every one of them resolves to
    /// a real entry — `GlossaryTests` is what keeps that true.
    public let related: [String]

    public var id: String { term }

    public init(_ term: String, _ definition: String, related: [String] = []) {
        self.term = term
        self.definition = definition
        self.related = related
    }
}

// MARK: - The glossary

public enum Glossary {

    /// Every term, sorted by name.
    ///
    /// Sorted on the lower-cased name rather than by a locale-aware
    /// comparison, so the order is the same on every platform the package
    /// builds on — including the one with no Mac in it.
    public static let all: [GlossaryTerm] = {
        let fromEnums: [GlossaryTerm] =
            WorkerJob.allCases.map { term(for: $0) }
            + HivePosture.allCases.map { term(for: $0) }
            + Pathogen.allCases.map { term(for: $0) }
            + Predator.allCases.map { term(for: $0) }
            + queenCellPurposes.map { term(for: $0) }
            + DeathCause.allCases.map { term(for: $0) }
            + HiveLocationType.allCases.map { term(for: $0) }
            + ResourceKind.allCases.map { term(for: $0) }

        return (freeStanding + fromEnums)
            .sorted { $0.term.lowercased() < $1.term.lowercased() }
    }()

    /// `QueenCell.Purpose` is the one keyed enum that is not `CaseIterable`,
    /// so its cases are listed here. The exhaustive switch in `term(for:)` is
    /// still what catches a new one at compile time; this list only decides
    /// what appears in `all`.
    public static let queenCellPurposes: [QueenCell.Purpose] = [
        .swarm, .supersedure, .emergency
    ]

    private static let index: [String: GlossaryTerm] = Dictionary(
        all.map { ($0.term.lowercased(), $0) },
        // A duplicate would be a bug, and `GlossaryTests` fails on one. Here
        // the first wins rather than trapping, because a crash in a glossary
        // is a worse outcome than a missing cross-reference.
        uniquingKeysWith: { first, _ in first }
    )

    public static func term(named name: String) -> GlossaryTerm? {
        index[name.lowercased()]
    }

    /// The entries a term points at, in the order it names them, skipping any
    /// that cannot be resolved.
    public static func relatedTerms(of term: GlossaryTerm) -> [GlossaryTerm] {
        term.related.compactMap { Self.term(named: $0) }
    }

    /// Search over both the word and its definition, so looking up "mite"
    /// finds varroa and looking up "swarm" finds the four entries about it.
    /// An empty query returns everything, so a search field can drive a list
    /// without the caller special-casing it.
    public static func search(_ query: String) -> [GlossaryTerm] {
        let needle = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !needle.isEmpty else { return all }

        return all.filter {
            $0.term.lowercased().contains(needle)
                || $0.definition.lowercased().contains(needle)
        }
    }

    /// Grouped by first letter, which is how a glossary is read.
    public struct LetterGroup: Identifiable, Equatable, Sendable {
        public let letter: String
        public let terms: [GlossaryTerm]
        public var id: String { letter }
    }

    public static func grouped(_ terms: [GlossaryTerm] = all) -> [LetterGroup] {
        var byLetter: [String: [GlossaryTerm]] = [:]
        for term in terms {
            let letter = String(term.term.prefix(1)).uppercased()
            byLetter[letter, default: []].append(term)
        }
        return byLetter
            .map { LetterGroup(letter: $0.key, terms: $0.value) }
            .sorted { $0.letter < $1.letter }
    }

    // MARK: - Terms that are not enum cases

    /// The concepts the engine models without naming in a type: how a colony
    /// divides, how it replaces a queen, how it fails, and the two or three
    /// botanical ideas the forage model turns on.
    public static let freeStanding: [GlossaryTerm] = [

        GlossaryTerm(
            "Absconding",
            "The colony gives up on the nest altogether and leaves — brood, comb, stores and all — rather than dividing. It is the last answer to a nest that has become untenable: comb eaten out by moth larvae, an infestation the cleaners cannot hold, a site that cannot be defended. A colony that absconds keeps nothing, least of all the cavity it had worked to extend.",
            related: ["Swarm", "Wax Moths", "Hive Beetles", "Under a Branch"]
        ),

        GlossaryTerm(
            "Afterswarm",
            "A second or third swarm, led by a virgin queen, in the days after the first one left with the old queen. Each takes more bees from a colony that is already halved and still has no laying queen, which is why a split here leaves one queen cell standing and knocks the rest down.",
            related: ["Swarm", "Swarm Cell", "Artificial Swarm", "Mating Flight"]
        ),

        GlossaryTerm(
            "Alarm Pheromone",
            "Isopentyl acetate, released from a gland beside the sting, which smells of bananas and calls every bee within range to the same spot. A roused colony defends itself far better than a quiet one — and it forages less while it is roused and loses more of the bees that sting, which is what a raid costs even when it is driven off.",
            related: ["Guard", "Hold the Entrance", "Died Defending", "Queen Pheromone"]
        ),

        GlossaryTerm(
            "Artificial Swarm",
            "Dividing the colony deliberately instead of waiting for it to swarm: the queen and the youngest bees go to a new nest, one queen cell is left standing, and the rest come down. Beekeepers call it a split. The foragers stay with the old nest and keep gathering, which is why it costs far less than the swarm it forestalls.",
            related: ["Swarm", "Afterswarm", "Swarm Cell", "Make Room"]
        ),

        GlossaryTerm(
            "Corolla Depth",
            "How far down a flower's tube the nectar sits, in millimetres. A worker's tongue is about 6.4 mm long and she can push her head in another 1.4, so nectar much deeper than 8 mm is beyond her however much of it there is. This one measurement is why white clover is the classic honey plant while red clover — the same genus, comparable nectar, a 9 mm tube — is famously useless to a honey bee.",
            related: ["Nectar", "Keystone Flower", "Waggle Dance"]
        ),

        GlossaryTerm(
            "Dearth",
            "A stretch when next to nothing is coming in and the colony lives on what it stored. Midsummer in a dry year is a dearth, autumn after the ivy is another, and winter is six months of one. The almanac records the day the income stops.",
            related: ["Nectar Flow", "Starvation", "Winter Cluster", "Evicted"]
        ),

        GlossaryTerm(
            "Drawn Comb",
            "Comb the bees have already built, as against empty cavity waiting to be built into. Wax costs roughly seven times its weight in honey, so a colony will not draw comb without a flow on — which is why drawn comb is the most valuable thing in a nest, and why room a congested colony cannot afford to use does nothing to stop it swarming.",
            related: ["Wax", "Comb Builder", "Nectar Flow", "Make Room"]
        ),

        GlossaryTerm(
            "Drone Layer",
            "A queen who never mated properly and can lay only unfertilised eggs, so every cell she fills becomes a drone. The colony is finished unless it replaces her, and usually it cannot: by the time the drone brood shows, there is no worker larva young enough to rear a queen from.",
            related: ["Mating Flight", "Patriline", "Emergency Cell", "Laying Workers"]
        ),

        GlossaryTerm(
            "Hygienic Behaviour",
            "The heritable tendency of workers to smell out diseased or infested brood, uncap the cell and haul the larva out. It is the strongest natural defence a colony has against chalkbrood and foulbrood, and against varroa it slows the mite without ever clearing it — at any moment about half the mites are riding adult bees, where no amount of uncapping reaches them.",
            related: ["Varroa Mites", "Chalkbrood", "American Foulbrood", "Patriline", "Mortuary"]
        ),

        GlossaryTerm(
            "Keystone Flower",
            "A plant that flowers when almost nothing else does, and so is worth far more to a colony than its yield alone: crocus and willow in February, ivy in October, mahonia in the middle of winter. The game marks them with a star, and scouts dance harder for them than for a richer plant in high summer.",
            related: ["Nectar Flow", "Dearth", "Waggle Dance"]
        ),

        GlossaryTerm(
            "Laying Workers",
            "With no queen and no brood young enough to rear one, the workers' own ovaries develop and they begin laying unfertilised eggs. The nest fills with drones and nothing can be done for it. This is the terminal state of queenlessness, and it is usually the last thing the almanac has to record.",
            related: ["Queen Pheromone", "Drone Layer", "Emergency Cell"]
        ),

        GlossaryTerm(
            "Mating Flight",
            "A virgin queen flies out once, meets a dozen or more drones from other colonies high in the air, and never mates again. Everything her colony will be — its disease resistance, its temper, its thrift — is settled in that one afternoon, and a week of bad weather can cost her the flight and the colony its future.",
            related: ["Patriline", "Drone Layer", "Supersedure", "Emergency Cell"]
        ),

        GlossaryTerm(
            "Nectar Flow",
            "A stretch when so much is coming in that the colony can rear brood, draw comb and store all at once. Flows are short and local — lime for a fortnight, oilseed rape while the field is yellow — and everything a colony does with its year is timed around them.",
            related: ["Dearth", "Nectar", "Drawn Comb", "Honey"]
        ),

        GlossaryTerm(
            "Patriline",
            "The daughters of one of the dozen-odd drones a queen mated with. Sisters from different patrilines differ in temper, in hygiene and in what they are good at, and that spread is most of a colony's resistance to disease. A poorly mated queen gives a uniform workforce that a single pathogen can go through from end to end.",
            related: ["Mating Flight", "Hygienic Behaviour", "Drone Layer"]
        ),

        GlossaryTerm(
            "Propolis Envelope",
            "Plant resin smeared over the whole inside of the nest. It is antimicrobial, and colonies that build a thorough envelope spend less on their own immune defence. The same resin is what a colony narrows an entrance with when it cannot hold the one it has.",
            related: ["Propolis", "Narrow the Entrance"]
        ),

        GlossaryTerm(
            "Queen Pheromone",
            "Queen mandibular pheromone: the signal that says the queen is here and well. It passes from bee to bee by contact, so it thins as the colony grows — which is precisely why big colonies swarm. Below about half strength the workers start queen cells; below a tenth, their own ovaries develop.",
            related: ["Swarm", "Supersedure", "Laying Workers", "Queen Attendant"]
        ),

        GlossaryTerm(
            "Supersedure",
            "The quiet replacement of a failing queen. The colony rears a daughter, she mates, the old queen goes, and the colony never divides. A colony that manages it in good time simply carries on, which is the whole difference between superseding and swarming.",
            related: ["Supersedure Cell", "Swarm", "Mating Flight"]
        ),

        GlossaryTerm(
            "Swarm",
            "How a colony reproduces. The old queen leaves with rather more than half the bees, gorged with honey, and the nest keeps the brood, the comb and a queen cell. Both halves are then in danger: the swarm has no comb and no stores, and what stayed behind has no laying queen until a virgin flies and comes back mated.",
            related: ["Afterswarm", "Swarm Cell", "Artificial Swarm", "Queen Pheromone", "Left with Swarm"]
        ),

        GlossaryTerm(
            "Waggle Dance",
            "A returning forager dances the direction and the distance of what she found on the face of the comb, and how hard she dances says how good it was. It makes a colony an optimiser: the richest, nearest patches are danced for hardest and draw the most bees. Here a patch's sugar, its distance and how much of it is left decide how many foragers it holds.",
            related: ["Forager", "Nectar", "Keystone Flower", "Corolla Depth"]
        ),

        GlossaryTerm(
            "Winter Bees",
            "Bees reared from late summer onward, and physiologically different animals: heavy fat bodies, glands that never wear out on brood food, six months of life instead of six weeks. They are what carries a colony to spring, and rearing enough of them is the most important thing it does in autumn.",
            related: ["Winter Cluster", "Nurse", "Old Age", "Dearth"]
        ),

        GlossaryTerm(
            "Winter Cluster",
            "The colony balls up and shivers, burning honey to hold the middle near 34 °C while there is brood and around 20 °C while there is not. A small cluster loses heat faster than it can make it, so how many bees go into winter matters quite as much as how much honey does.",
            related: ["Winter Bees", "Honey", "Chilled Brood", "Starvation"]
        )
    ]

    // MARK: - What a bee is doing

    public static func term(for job: WorkerJob) -> GlossaryTerm {
        switch job {
        case .cellCleaner:
            return GlossaryTerm(
                job.displayName,
                "A worker's first job, in her first two days: polishing an empty cell until the queen will lay in it. An unpolished cell gets no egg, so a colony with nobody young enough to clean stops rearing brood before it runs out of room.",
                related: ["Nurse", "Drawn Comb"]
            )
        case .nurseBee:
            return GlossaryTerm(
                job.displayName,
                "A worker of about two to eleven days old, feeding larvae from her own brood-food glands. Brood rearing is limited by how many nurses there are and how much bee bread they have to eat, not by how fast the queen can lay.",
                related: ["Royal Jelly", "Bee Bread", "Winter Bees"]
            )
        case .mortuary:
            return GlossaryTerm(
                job.displayName,
                "Undertakers, who carry the dead out of the nest and drop them well clear of it. Unglamorous and load-bearing: a colony that cannot clear its dead is a colony with disease in the comb.",
                related: ["Hygienic Behaviour", "Chalkbrood", "Send in the Cleaners"]
            )
        case .droneFeeder:
            return GlossaryTerm(
                job.displayName,
                "Drones are fed by workers for much of their lives, being poor at it themselves. When the flow stops the colony stops feeding them, and shortly after that it throws them out.",
                related: ["Evicted", "Dearth"]
            )
        case .queenAttendant:
            return GlossaryTerm(
                job.displayName,
                "The retinue that grooms and feeds the queen and carries her pheromone out through the colony by contact. They are how every other bee knows she is alive.",
                related: ["Queen Pheromone", "Supersedure"]
            )
        case .nectarConcentrator:
            return GlossaryTerm(
                job.displayName,
                "House bees who ripen nectar into honey, working it between their mouthparts and fanning the water off. Thin nectar is far more work than thick, which is why sugar concentration counts for as much as volume.",
                related: ["Nectar", "Honey", "Fanner"]
            )
        case .pollenPacker:
            return GlossaryTerm(
                job.displayName,
                "Workers who ram incoming pollen down into cells and seal it under a film of honey, where it keeps as bee bread.",
                related: ["Pollen", "Bee Bread"]
            )
        case .honeycombBuilder:
            return GlossaryTerm(
                job.displayName,
                "Wax secreted in flakes from glands under the abdomen, chewed soft and drawn into cells. At roughly seven units of honey for one of wax, building happens on a flow or not at all.",
                related: ["Wax", "Drawn Comb", "Nectar Flow"]
            )
        case .fanning:
            return GlossaryTerm(
                job.displayName,
                "Bees standing at the entrance and over open cells, moving air through the nest to hold the brood near 34 °C and to drive water out of stored nectar.",
                related: ["Overheating", "Water Carrier", "Nectar Concentrator"]
            )
        case .waterCarrier:
            return GlossaryTerm(
                job.displayName,
                "Foragers bringing water rather than nectar, for cooling the nest and for thinning honey to feed brood. It is the one job with no age limit at all: any bee that can fly will do it.",
                related: ["Water", "Fanner", "Overheating"]
            )
        case .guardBee:
            return GlossaryTerm(
                job.displayName,
                "For a few days around her eighteenth, a worker stands at the entrance and checks every bee that comes in by scent. Guards are what stops a robbing, and what raises the alarm when something worse arrives.",
                related: ["Alarm Pheromone", "Robber Bees", "Hold the Entrance"]
            )
        case .foragingBee:
            return GlossaryTerm(
                job.displayName,
                "The last job of a worker's life, from about three weeks old until she wears out. Foragers are the only bees that bring anything in, and they fly a few miles at most — which is why how far away a patch is matters so much.",
                related: ["Waggle Dance", "Nectar", "Pollen", "Old Age"]
            )
        }
    }

    // MARK: - The stance the player can take

    public static func term(for posture: HivePosture) -> GlossaryTerm {
        switch posture {
        case .instinct:
            return GlossaryTerm(
                posture.displayName,
                "The default, and what happens when nobody answers: the colony does what a colony does. Leaving it alone costs nothing that instinct would not have cost anyway, which is the promise this game makes about not being a pager.",
                related: ["Hold the Entrance", "Make Room"]
            )
        case .holdEntrance:
            return GlossaryTerm(
                posture.displayName,
                "Every bee that can sting meets the attacker at the door. It is the strongest answer to anything that comes to the entrance, and it is paid for twice: in foragers who are not in the field, and in defenders, because a bee that stings a mammal dies of it.",
                related: ["Alarm Pheromone", "Guard", "Died Defending", "Hornet"]
            )
        case .narrowEntrance:
            return GlossaryTerm(
                posture.displayName,
                "Propolis narrows the way in to a slot: hard to force, hard to rob, and too small for a mouse. It also slows every forager going through it, all day.",
                related: ["Propolis Envelope", "Mouse", "Robber Bees", "Ants"]
            )
        case .foragersHome:
            return GlossaryTerm(
                posture.displayName,
                "Nobody goes out. Against something that takes bees in the field — a bee-eater over the nest, a crab spider in the flowers — there is nothing left to take, and equally nothing coming in.",
                related: ["Bee Eater", "Crab Spider", "Forager"]
            )
        case .cleanersOut:
            return GlossaryTerm(
                posture.displayName,
                "Cleaners and undertakers turned out in force to hunt moth and beetle larvae through the comb, at the expense of everything else they would have been doing.",
                related: ["Wax Moths", "Hive Beetles", "Mortuary"]
            )
        case .makeRoom:
            return GlossaryTerm(
                posture.displayName,
                "Builders draw comb and foragers hold back, to ease the crowding that sends a swarm out. It lowers the odds without removing them, which is about what a beekeeper achieves by giving a colony room.",
                related: ["Swarm", "Drawn Comb", "Artificial Swarm"]
            )
        }
    }

    // MARK: - What can be wrong inside

    public static func term(for pathogen: Pathogen) -> GlossaryTerm {
        switch pathogen {
        case .varroa:
            return GlossaryTerm(
                pathogen.displayName,
                "Varroa destructor, a mite the size of a pinhead that breeds inside sealed brood and feeds on the pupa. It is why most managed colonies die, though rarely directly: what kills is the viruses it carries, usually in the colony's second autumn, which is why the collapse always looks sudden.",
                related: ["Deformed Wing Virus", "Hygienic Behaviour", "Disease"]
            )
        case .deformedWingVirus:
            return GlossaryTerm(
                pathogen.displayName,
                "A virus that varroa carries from bee to bee. The bees emerge with crumpled wings that will never fly, and the colony's next generation of foragers quietly fails to arrive. Hygienic workers reach only part of it, because the virus is in the adults as much as in the brood.",
                related: ["Varroa Mites", "Forager", "Hygienic Behaviour"]
            )
        case .nosema:
            return GlossaryTerm(
                pathogen.displayName,
                "A gut parasite of adult bees, worst after a long confinement when they cannot get out to defecate. It shortens lives rather than killing outright, and nothing the workers do in the comb touches it.",
                related: ["Winter Cluster", "Disease"]
            )
        case .chalkbrood:
            return GlossaryTerm(
                pathogen.displayName,
                "A fungus that mummifies larvae into hard chalky pellets. A damp, chilled brood nest brings it on, and hygienic workers can clear all of it if they are inclined to.",
                related: ["Hygienic Behaviour", "Chilled Brood", "Mortuary"]
            )
        case .americanFoulbrood:
            return GlossaryTerm(
                pathogen.displayName,
                "A bacterial brood disease and the most serious here: the larvae rot in their cells and the spores last for decades. Hygienic behaviour reaches all of it in principle, but it grows faster than anything else the colony has to fight.",
                related: ["Hygienic Behaviour", "Disease", "Mortuary"]
            )
        }
    }

    // MARK: - What comes for the nest

    public static func term(for predator: Predator) -> GlossaryTerm {
        switch predator {
        case .bear:
            return GlossaryTerm(
                predator.displayName,
                "Comes for brood and honey and takes the nest apart to get them. No posture reaches it, and a colony does not survive the visit.",
                related: ["Honey Badger", "Human", "Absconding"]
            )
        case .badger:
            return GlossaryTerm(
                predator.displayName,
                "Thick-skinned, indifferent to stinging, and after the brood. Like a bear, it destroys the nest rather than raiding it — and it digs, so underground is no protection.",
                related: ["Bear", "Animal Burrow"]
            )
        case .skunk:
            return GlossaryTerm(
                predator.displayName,
                "Scratches at the entrance after dark and eats the bees that come out to see what it is. The colony loses defenders night after night rather than all at once.",
                related: ["Hold the Entrance", "Raccoon", "Opossum"]
            )
        case .raccoon:
            return GlossaryTerm(
                predator.displayName,
                "Dextrous and persistent at the entrance, pulling out comb wherever it can reach one.",
                related: ["Skunk", "Hold the Entrance"]
            )
        case .opossum:
            return GlossaryTerm(
                predator.displayName,
                "A night visitor at the entrance, picking off bees as they come and go. More nuisance than catastrophe.",
                related: ["Skunk", "Hold the Entrance"]
            )
        case .mouse:
            return GlossaryTerm(
                predator.displayName,
                "Moves in during autumn and spends the winter in the comb, chewing it up for a nest while the cluster is too cold to drive her out. A narrowed entrance keeps her out; once she is in, nothing does.",
                related: ["Narrow the Entrance", "Winter Cluster"]
            )
        case .human:
            return GlossaryTerm(
                predator.displayName,
                "A nest in a wall or a chimney, found by somebody who would rather it were not there. There is no answer to this one either.",
                related: ["Inside a Wall", "Human Structure", "Bear"]
            )
        case .beeEater:
            return GlossaryTerm(
                predator.displayName,
                "Takes foragers on the wing in the open air near the nest. Keeping the foragers home is the only answer, and it costs the day's income.",
                related: ["Keep the Foragers Home", "Forager"]
            )
        case .honeyBuzzard:
            return GlossaryTerm(
                predator.displayName,
                "A raptor that digs nests out for the brood and the comb. Rare, and serious where it happens.",
                related: ["Bee Eater", "Hold the Entrance"]
            )
        case .woodpecker:
            return GlossaryTerm(
                predator.displayName,
                "Hammers a hole into a winter cavity and feeds on the cluster through it, which leaves the nest open as well as smaller.",
                related: ["Winter Cluster", "Narrow the Entrance"]
            )
        case .shrike:
            return GlossaryTerm(
                predator.displayName,
                "Catches bees in the field and impales them on thorns to come back to.",
                related: ["Bee Eater", "Keep the Foragers Home"]
            )
        case .wasp:
            return GlossaryTerm(
                predator.displayName,
                "In late summer, with no brood of their own left to feed, wasps turn to robbing: the bees at the entrance first, then the honey behind them. The commonest threat in the game, and the one a narrow entrance answers best.",
                related: ["Hornet", "Robber Bees", "Narrow the Entrance"]
            )
        case .hornet:
            return GlossaryTerm(
                predator.displayName,
                "Hunts bees at the entrance and carries them off whole. Far fewer of them than wasps, and much worse per visit.",
                related: ["Wasp", "Hold the Entrance"]
            )
        case .robberBee:
            return GlossaryTerm(
                predator.displayName,
                "Bees from another colony stealing stores, which they will do to any nest weak enough to let them in. Robbing feeds on itself: a colony that loses the entrance loses everything behind it.",
                related: ["Guard", "Narrow the Entrance", "Honey"]
            )
        case .ant:
            return GlossaryTerm(
                predator.displayName,
                "Pilfer stores and brood a little at a time without ever fighting for the entrance. Attrition rather than assault.",
                related: ["Narrow the Entrance", "Honey"]
            )
        case .waxMoth:
            return GlossaryTerm(
                predator.displayName,
                "Lay in the comb, and the larvae tunnel through it eating wax, pollen and brood as they go. A strong colony's cleaners keep them down; a weak one is eaten out of its own nest and absconds.",
                related: ["Send in the Cleaners", "Wax", "Absconding"]
            )
        case .hiveBeetle:
            return GlossaryTerm(
                predator.displayName,
                "Small hive beetles breed in the comb and foul stored honey until it ferments and runs. Cleaners can hold them; a shrinking colony cannot.",
                related: ["Send in the Cleaners", "Wax Moths", "Honey"]
            )
        case .crabSpider:
            return GlossaryTerm(
                predator.displayName,
                "Sits in a flower, coloured like the flower, and takes the forager that lands on it. The one predator the player's own photographs send bees towards.",
                related: ["Keep the Foragers Home", "Forager", "Praying Mantis"]
            )
        case .prayingMantis:
            return GlossaryTerm(
                predator.displayName,
                "Waits among flowers or at the entrance and takes bees one at a time, patiently.",
                related: ["Crab Spider", "Keep the Foragers Home"]
            )
        case .dragonfly:
            return GlossaryTerm(
                predator.displayName,
                "Catches bees in flight in the open, and turns faster than they can.",
                related: ["Bee Eater", "Keep the Foragers Home"]
            )
        case .toad:
            return GlossaryTerm(
                predator.displayName,
                "Sits under the entrance in the evening and eats the bees that walk out past it.",
                related: ["Hold the Entrance", "Opossum"]
            )
        }
    }

    // MARK: - Why a queen is being reared

    public static func term(for purpose: QueenCell.Purpose) -> GlossaryTerm {
        switch purpose {
        case .swarm:
            return GlossaryTerm(
                purpose.displayName,
                "Queen cells raised because the colony means to divide — several at once, hung along the bottom edge of the comb. The old queen leaves before the first of them emerges, which is what makes finding them a warning rather than a report.",
                related: ["Swarm", "Afterswarm", "Make Room", "Artificial Swarm"]
            )
        case .supersedure:
            return GlossaryTerm(
                purpose.displayName,
                "A cell or two raised in the middle of the comb to replace a queen who is failing, without the colony dividing at all. The quiet way to change queens.",
                related: ["Supersedure", "Mating Flight"]
            )
        case .emergency:
            return GlossaryTerm(
                purpose.displayName,
                "Raised in a hurry from an ordinary worker larva after the queen is suddenly lost. The larva is usually already too old for the job, so the queen who emerges is a poor one — and if there is no young brood at all, there is no queen.",
                related: ["Laying Workers", "Drone Layer", "Mating Flight"]
            )
        }
    }

    // MARK: - What a bee dies of

    public static func term(for cause: DeathCause) -> GlossaryTerm {
        switch cause {
        case .oldAge:
            return GlossaryTerm(
                cause.displayName,
                "A summer worker wears out in about six weeks, most of it spent flying. Foragers do not retire; they simply fail to come back.",
                related: ["Forager", "Winter Bees"]
            )
        case .starvation:
            return GlossaryTerm(
                cause.displayName,
                "The stores run out. It happens far more in late winter and early spring than in the dearth itself, because a colony that has started rearing brood again is spending fast with nothing yet coming in.",
                related: ["Dearth", "Honey", "Winter Cluster"]
            )
        case .chill:
            return GlossaryTerm(
                cause.displayName,
                "Brood left uncovered when the cluster contracts, or a nest too cold to hold 34 °C. The larvae die where they lie, and what is lost is three weeks of the colony's future.",
                related: ["Winter Cluster", "Chalkbrood", "Fanner"]
            )
        case .overheating:
            return GlossaryTerm(
                cause.displayName,
                "Much above 36 °C the brood cooks. The colony answers with water and fanning, which costs it a day's foraging to do.",
                related: ["Fanner", "Water Carrier", "Water"]
            )
        case .disease:
            return GlossaryTerm(
                cause.displayName,
                "Death from infection, whichever pathogen it was. Most of it is varroa's viruses rather than varroa itself.",
                related: ["Varroa Mites", "Deformed Wing Virus", "Hygienic Behaviour"]
            )
        case .predation:
            return GlossaryTerm(
                cause.displayName,
                "Taken by something: at the entrance, in the comb, or out in the field where the flowers are.",
                related: ["Wasp", "Bee Eater", "Hold the Entrance"]
            )
        case .evicted:
            return GlossaryTerm(
                cause.displayName,
                "Drones, put out of the nest to starve when the flow ends. A colony that has stopped feeding them cannot carry them through winter, and once the queens are mated they have no other purpose.",
                related: ["Drone Feeder", "Dearth", "Mating Flight"]
            )
        case .swarmed:
            return GlossaryTerm(
                cause.displayName,
                "Not a death at all: these bees left with the swarm and are alive somewhere else. The colony counts them gone because from its side of the entrance they are.",
                related: ["Swarm", "Artificial Swarm", "Afterswarm"]
            )
        case .stungIntruder:
            return GlossaryTerm(
                cause.displayName,
                "A bee that stings a mammal leaves the sting and much of her abdomen behind and dies within hours. Every defence at the entrance is paid for in bees.",
                related: ["Alarm Pheromone", "Guard", "Hold the Entrance"]
            )
        }
    }

    // MARK: - Where the colony lives

    public static func term(for site: HiveLocationType) -> GlossaryTerm {
        switch site {
        case .livingTreeCavity:
            return GlossaryTerm(
                site.displayName,
                "A hollow in a living tree, which is what a swarm chooses when it is given the choice: roomy, insulated by wood that is still alive, and usually high enough to be hard to reach.",
                related: ["Swarm", "Winter Cluster", "Fallen Tree"]
            )
        case .fallenTree:
            return GlossaryTerm(
                site.displayName,
                "A hollow trunk lying on the ground. A fair size, and the rotten wood can be chewed away for more — but damp, and within reach of anything that walks.",
                related: ["Living Tree Cavity", "Mouse"]
            )
        case .underTreeBranch:
            return GlossaryTerm(
                site.displayName,
                "Open comb hanging in the air with no cavity around it. Beautiful, tiny, cold and indefensible: a colony here will not see winter.",
                related: ["Winter Cluster", "Absconding"]
            )
        case .cliff:
            return GlossaryTerm(
                site.displayName,
                "Comb in a crevice in rock. Cramped and draughty, with nowhere to extend to — but hard for anything heavy to climb to.",
                related: ["Make Room", "Cave"]
            )
        case .cave:
            return GlossaryTerm(
                site.displayName,
                "The most room there is, and safe with it. Cold, though, so the cluster spends more honey holding its heat than it would in a tree.",
                related: ["Winter Cluster", "Honey"]
            )
        case .insideWalls:
            return GlossaryTerm(
                site.displayName,
                "A cavity in a building: warm, roomy, easily held, and it runs on along the wall when the nest needs more room. The best site in the game, until somebody notices.",
                related: ["Human", "Human Structure", "Make Room"]
            )
        case .humanStructure:
            return GlossaryTerm(
                site.displayName,
                "A shed roof, a chimney, a disused box. Warm, reasonably large, and as permanent as the owner allows.",
                related: ["Inside a Wall", "Human"]
            )
        case .termiteMound:
            return GlossaryTerm(
                site.displayName,
                "Thick earth walls, which hold heat well, around a middling amount of room.",
                related: ["Animal Burrow", "Winter Cluster"]
            )
        case .animalBurrow:
            return GlossaryTerm(
                site.displayName,
                "Underground: warm, well hidden, damp, and easy for anything that digs to open up.",
                related: ["Honey Badger", "Termite Mound"]
            )
        case .nestbox:
            return GlossaryTerm(
                site.displayName,
                "Built for bees. Modest and unremarkable, which is the point — and the one site where more room is a matter of putting another box on top.",
                related: ["Make Room", "Drawn Comb"]
            )
        }
    }

    // MARK: - What the colony handles

    public static func term(for resource: ResourceKind) -> GlossaryTerm {
        switch resource {
        case .nectar:
            return GlossaryTerm(
                resource.displayName,
                "Sugar water from flowers, anywhere from 15% to 60% sugar by weight. It is unripe honey, and it ferments if it is left alone, so it has to be worked and fanned down before it will keep.",
                related: ["Honey", "Nectar Concentrator", "Corolla Depth", "Nectar Flow"]
            )
        case .pollen:
            return GlossaryTerm(
                resource.displayName,
                "The colony's only source of protein, at roughly 12% to 30% crude protein depending on the plant. The amino acid profile counts as much as the quantity: dandelion pollen is short of four essential ones, and brood reared on it alone does badly however much of it comes in.",
                related: ["Bee Bread", "Pollen Packer", "Nurse"]
            )
        case .water:
            return GlossaryTerm(
                resource.displayName,
                "Carried in for cooling the nest and for thinning stored honey to feed brood. It is used as it arrives rather than stored in cells, and what is not used evaporates.",
                related: ["Water Carrier", "Fanner", "Overheating"]
            )
        case .propolis:
            return GlossaryTerm(
                resource.displayName,
                "Resin gathered from buds and bark and used as glue, sealant and antiseptic. It is what a colony narrows its entrance with, and what it lines the whole nest in.",
                related: ["Propolis Envelope", "Narrow the Entrance"]
            )
        case .honey:
            return GlossaryTerm(
                resource.displayName,
                "Nectar ripened down to about 18% water and capped under wax, where it keeps indefinitely. It is the colony's entire winter, and everything else it spends — wax, warmth, brood food — is paid for out of it.",
                related: ["Nectar", "Wax", "Winter Cluster", "Starvation"]
            )
        case .beeBread:
            return GlossaryTerm(
                resource.displayName,
                "Pollen rammed into cells under a film of honey, where it ferments and keeps. This, rather than raw pollen, is what the nurses actually eat.",
                related: ["Pollen", "Nurse", "Pollen Packer"]
            )
        case .royalJelly:
            return GlossaryTerm(
                resource.displayName,
                "Brood food from the nurses' head glands. Every larva is fed it for its first three days; a larva fed nothing else becomes a queen. It is glandular and perishes within days, so it cannot be stored against a shortage.",
                related: ["Nurse", "Swarm Cell", "Emergency Cell"]
            )
        case .wax:
            return GlossaryTerm(
                resource.displayName,
                "Secreted in flakes from glands under a worker's abdomen and chewed into comb. At about seven units of honey to one of wax, it is the most expensive thing a colony makes.",
                related: ["Drawn Comb", "Comb Builder", "Honey"]
            )
        }
    }
}
