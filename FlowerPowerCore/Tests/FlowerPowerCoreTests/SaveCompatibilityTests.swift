import Testing
import Foundation
@testable import FlowerPowerCore

/// Every save ever written must still open.
///
/// The rule is stated in `World.init(from:)`: a synthesised decoder throws on
/// a missing key, even for a property with a default, so a property added to
/// any type in the save turns every save written before it into a file that
/// will not decode. `GameStore.load` used to treat such a file as no save and
/// start again over it. It keeps the file now, but a colony the player cannot
/// open is still a colony they have lost.
///
/// So this takes a real save, with every kind of thing a save can hold in it,
/// and takes its keys out one at a time — every key, at every depth — and
/// requires the save to open without each. A key that has been in the file
/// since the first save ever written may be genuinely required, and those are
/// named in `requiredKeys` with the reason. Anything not on that list must be
/// optional to the decoder.
///
/// **What this catches.** A new stored property on any type in the save. Its
/// key is not on the list, the save will not open without it, and the case
/// named after its path fails. The fix is almost never to add it to the list —
/// it cannot have been in the first save — but to decode it with
/// `decodeIfPresent` and a default, the way `World` and `SimulationConfig` do.
///
/// Beside it, `Fixtures/` holds saves written by earlier builds, and each must
/// still decode. The synthetic check above only knows about keys that exist
/// today; a fixture is the old file itself.
@Suite("Save compatibility")
struct SaveCompatibilityTests {

    // MARK: - Round trip

    @Test("A save decodes to exactly the colony that wrote it")
    func roundTrip() throws {
        let decoded = try Self.decoder().decode(Simulation.self, from: Self.save)
        #expect(decoded == Self.colony)
    }

    // MARK: - One key at a time

    @Test("A save still opens with any one key missing", arguments: removableKeys)
    func opensWithoutKey(_ path: String) throws {
        let older = try Self.save(without: path)
        let loss = Self.loss(opening: older, without: path)
        #expect(loss == nil, "without \(path), \(loss ?? "")")
    }

    /// The allow-list is only worth anything while it is exact. A key on it
    /// that no save contains is a property that was renamed or removed, and a
    /// key on it that a save can do without has been given a default since —
    /// either way the entry is now hiding nothing and should come off.
    @Test("Every key the allow-list calls required is in the save, and is required")
    func allowListIsCurrent() throws {
        for path in Self.requiredKeys.sorted() {
            guard Self.keys[path] != nil else {
                Issue.record("\(path) is listed as required, but no save contains it")
                continue
            }
            let older = try Self.save(without: path)
            #expect(
                Self.loss(opening: older, without: path) != nil,
                "\(path) is listed as required, but a save does without it"
            )
        }
    }

    /// What opening a save cost, or nil if it came through whole.
    ///
    /// Not only whether it decodes. Two parts of the save are decoded to
    /// survive damage by dropping it — `ColonyHistory` loses the whole record
    /// rather than the colony, and `Milestones` loses the one badge — and a
    /// field added to either would open every old save without its charts or
    /// its badges. That is the same bug, quieter, so it counts here too.
    ///
    /// Only for a key *inside* a sample or a record. A save with no history
    /// or no milestones at all is one written before either existed, and
    /// opening it with none is exactly right.
    static func loss(opening data: Data, without path: String) -> String? {
        let decoded: Simulation
        do {
            decoded = try decoder().decode(Simulation.self, from: data)
        } catch {
            return "the save would not open: \(error)"
        }
        if path.hasPrefix("world.history.samples[]."),
           decoded.history.samples.count != colony.history.samples.count {
            return "the save opened without its history"
        }
        if path.hasPrefix("world.milestones.achieved[]."),
           decoded.milestones.count != colony.milestones.count {
            return "the save opened without a milestone"
        }
        return nil
    }

    // MARK: - What a missing key becomes

    /// The config is the type that grows fastest. A key it did not have is
    /// today's standard value, and nothing else in it moves.
    @Test("A config key a save does not have takes the standard value")
    func missingConfigKeyTakesTheDefault() throws {
        var harsh = Self.colony
        harsh.config = .harsh
        #expect(harsh.config.nectarPerForager != SimulationConfig.standard.nectarPerForager)

        let older = try Self.save(of: harsh, without: "config.wildPatchDensity")
        let decoded = try Self.decoder().decode(Simulation.self, from: older)

        #expect(decoded.config.wildPatchDensity == SimulationConfig.standard.wildPatchDensity)
        #expect(
            decoded.config.nectarPerForager == SimulationConfig.harsh.nectarPerForager,
            "the preset the colony was started on survives"
        )
        #expect(decoded.config == harsh.config)
    }

    /// The other way to get a hand-written decoder wrong: forget a line. The
    /// key still decodes — to its default, whatever the save said — so no
    /// save fails to open and nothing above notices. Every config property is
    /// moved off its default here, and each must come back as it went in.
    @Test("Every config key a save holds is read back, not left at its default")
    func everyConfigKeyIsRead() throws {
        var document: [String: Any] = [:]
        for child in Mirror(reflecting: SimulationConfig.standard).children {
            guard let label = child.label else { continue }
            let kind = type(of: child.value)
            if kind == Double.self, let value = child.value as? Double {
                document[label] = value + 0.5
            } else if kind == Int.self, let value = child.value as? Int {
                document[label] = value + 1
            } else if kind == Optional<Double>.self {
                document[label] = 0.375
            } else {
                Issue.record("config.\(label) is a \(kind), which this test cannot move")
            }
        }

        let decoded = try Self.decoder().decode(
            SimulationConfig.self, from: JSONSerialization.data(withJSONObject: document)
        )

        // Every property here is a number, and an optional one unwraps.
        func number(_ value: Any) -> Double? {
            (value as? Double) ?? (value as? Int).map(Double.init)
        }
        for child in Mirror(reflecting: decoded).children {
            guard let label = child.label, let expected = document[label] else { continue }
            #expect(
                number(child.value) == number(expected),
                "config.\(label) was saved but not read back"
            )
        }
    }

    /// A species saved before forage came from floral traits has neither a
    /// taxon nor traits, and is given the catalogue's description of itself.
    @Test("A species saved before taxonomy is described from the catalogue")
    func speciesWithoutTaxonomy() throws {
        let clover = FlowerCatalogue.whiteClover
        var object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(clover))
                as? [String: Any]
        )
        object.removeValue(forKey: "taxon")
        object.removeValue(forKey: "traits")
        // What a species carried then instead.
        object["scientificName"] = "Trifolium repens"
        object["nectarRichness"] = 1.2
        object["pollenRichness"] = 0.9

        let decoded = try JSONDecoder().decode(
            FlowerSpecies.self, from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(decoded == clover)

        // And one the catalogue has never heard of is a middling flower rather
        // than an error.
        object["id"] = "no-such-flower"
        let stranger = try JSONDecoder().decode(
            FlowerSpecies.self, from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(stranger.taxon == FlowerSpecies.unidentified.taxon)
        #expect(stranger.traits == FlowerSpecies.unidentified.taxon.family.typicalTraits)
    }

    // MARK: - Saves written by earlier builds

    @Test("Every checked-in save still opens", arguments: fixtureNames)
    func fixtureOpens(_ name: String) throws {
        let url = try #require(Self.fixturesDirectory?.appendingPathComponent(name))
        let decoded = try Self.decoder().decode(Simulation.self, from: Data(contentsOf: url))

        #expect(decoded.clock.day > 0)
        #expect(!decoded.world.hive.bees.isEmpty)
        // And what it opens as is stable: this build writes it and reads it
        // back as the same colony.
        let again = try Self.decoder().decode(
            Simulation.self, from: Self.encoder().encode(decoded)
        )
        #expect(again == decoded)
    }

    @Test("There is at least one checked-in save")
    func fixturesArePresent() {
        #expect(!Self.fixtureNames.isEmpty, "Fixtures/ did not reach the test bundle")
    }

    /// Writes today's save into `Fixtures/`. Off unless asked for.
    ///
    /// **When to run it.** Only when the save format has changed on purpose —
    /// a type gained a key, say — and the change should be held from now on.
    /// Run
    ///
    ///     $env:FLOWERPOWER_WRITE_SAVE_FIXTURE = "1"
    ///     swift test --filter SaveCompatibilityTests
    ///     Remove-Item Env:FLOWERPOWER_WRITE_SAVE_FIXTURE
    ///
    /// (`FLOWERPOWER_WRITE_SAVE_FIXTURE=1 swift test …` in a POSIX shell) and
    /// commit the new `save-<today>.json` beside the old ones.
    ///
    /// **Add, never replace.** The point of an old fixture is that it is old:
    /// it is the file a player who has not opened the app since that day still
    /// has. If one stops decoding, the change that broke it is the bug. Delete
    /// one only when a format change deliberately abandons every save written
    /// before it, and say so in the commit.
    @Test(
        "Write today's save as a fixture",
        .enabled(if: ProcessInfo.processInfo.environment["FLOWERPOWER_WRITE_SAVE_FIXTURE"] != nil)
    )
    func writeFixture() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        let name = "save-\(formatter.string(from: Date())).json"

        // Pretty-printed and sorted, so a reader can find their way round it
        // and a diff between two fixtures means something. The decoder does
        // not care; a player's save is the same JSON without the whitespace.
        let encoder = Self.encoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Self.colony).write(to: directory.appendingPathComponent(name))
    }

    // MARK: - Keys that were in the first save

    /// Keys a save cannot do without, with why.
    ///
    /// Grouped by the object they sit in, by path. A path is the chain of
    /// keys from the top of the file, with `[]` for "any element of this
    /// array": `world.hive.bees[].kind` is the kind of every bee.
    ///
    /// Everything here was in the first save any build wrote, on or before
    /// 2026-09-05, or was in the first save its type ever appeared in — so no
    /// save can lack it except a damaged one, and a default would be a
    /// fabrication rather than a reading. The types these keys belong to
    /// decode by synthesis, and that is only safe while this list is complete:
    /// a property added to one of them is not on it, and fails above.
    static let requiredGroups: [String: [String]] = {
        var groups: [String: [String]] = [
            // The colony, the clock, the balance numbers, and the two
            // streams that make it deterministic: without any one of them
            // there is nothing to resume.
            "": ["world", "clock", "config", "rng", "ids"],
            "rng": ["state"],
            "ids": ["nextValue"],
            // The seasonal clock's two newer fields are decoded with defaults
            // in `SimClock.init(from:)`; these four are the clock.
            "clock": ["epoch", "tick", "realSecondsPerTick", "maxCatchUpDays"],

            // `World.init(from:)` defaults everything that arrived after the
            // first save; these are what it had then.
            "world": [
                "hive", "patches", "weather", "attackHistory",
                "recentNectarIntake", "todayNectarIntake"
            ],
            "world.weather": ["sky", "temperatureCelsius", "humidity", "windSpeed"],

            "world.hive": [
                "location", "bees", "resources", "comb", "temperatureCelsius",
                "humidity", "pathogens", "pheromones", "genetics", "broodUpgrade",
                "daysQueenless", "hasLayingWorkers", "queenIsMated", "propolisEnvelope"
            ],
            "world.hive.location": ["type"],
            "world.hive.resources": ["amounts"],
            "world.hive.pathogens": ["levels"],
            "world.hive.pheromones": ["queenMandibular", "brood", "alarm", "nasonov"],
            "world.hive.comb": ["cells", "queenCells", "capacity"],
            // An entity's identity and what it is for.
            "world.hive.comb.queenCells[]": ["id", "purpose", "daysDeveloped", "quality"],

            // `FlowerPatch.init(from:)` defaults its later arrivals; these
            // were there from the start. `species` is optional throughout.
            "world.patches[]": [
                "id", "photoLocalIdentifier", "identificationConfidence",
                "distanceMetres", "discoveredAt", "remainingNectar",
                "remainingPollen", "nectarCapacity", "pollenCapacity",
                "recruitedForagers"
            ],
            // `FlowerSpecies.init(from:)` fills `taxon` and `traits` from the
            // catalogue; the rest is the species' identity.
            "world.patches[].species": [
                "id", "commonName", "rarity", "bloomSeasons", "isKeystone"
            ],
            // Arrived with `taxon` and `traits` themselves, on 2026-09-06, and
            // unchanged since. The genus and epithet are optional.
            "world.patches[].species.taxon": ["family"],
            "world.patches[].species.traits": [
                "corollaDepthMillimetres", "nectarSugarConcentration", "nectarVolume",
                "pollenProteinFraction", "pollenAminoAcidCompleteness",
                "pollenAbundance", "producesNectar"
            ],
            "world.patches[].cell": ["q", "r"],

            "world.attackHistory[]": [
                "id", "predator", "day", "wasRepelled", "beesLost", "storesLost", "combLost"
            ],

            // The decision and record types below each arrived whole, on the
            // date in the comment, as a key `World` decodes with a default.
            // Nothing has been added to any of them since.

            // 2026-09-06.
            "world.activeThreat": ["predator", "beganOnDay", "resolvesOnDay"],
            "world.pendingSwarm": ["startedOnDay", "departsOnDay", "discouraged"],
            "world.lastSwarm": ["day", "queen", "workers", "genetics", "honeyCarried"],
            "world.lineage": ["queens", "generation"],
            "world.lineage.queens[]": ["number", "emergedOnDay", "quality"],
            "world.almanac.entries[]": ["day", "season", "kind", "text"],
            // The tallies themselves are defaulted in `Almanac.init(from:)`;
            // each one arrived with all its counts.
            "world.almanac.tallies[]": [
                "year", "swarms", "splits", "queensRaised", "queensMated", "raids",
                "raidsRepelled", "infections", "honeyTaken", "peakHoney", "combAdded"
            ],

            // 2026-09-12. Neither of these stops a save opening — a record
            // missing one of these costs the colony that badge, and a sample
            // missing one costs it the whole history — but either is a loss,
            // and `loss(opening:)` counts it.
            "world.milestones.achieved[]": ["milestone", "day"],
            "world.history.samples[]": [
                "day", "adults", "brood", "workers", "drones", "winterBees",
                "edibleEnergy", "winterRequirement", "nestTemperature",
                "outsideTemperature", "combCells", "nectarIntake", "alarm", "status"
            ],

            // 2026-09-15, with the world.
            "world.terrain": ["seed", "home", "discovered", "gardenRings"],
            "world.terrain.home": ["q", "r"],
            "world.terrain.discovered[]": ["q", "r"],

            // 2026-09-16.
            "world.scoutingParty": ["leftOnDay", "returnsOnDay"]
        ]

        // One bee is one shape wherever it is saved.
        let bee = [
            "id", "kind", "stage", "daysInStage", "patriline", "vitality", "wear",
            "physiology", "behaviouralAge"
        ]
        let genetics = [
            "patrilines", "hygienicBehaviour", "defensiveness", "fecundity",
            "swarminess", "thriftiness"
        ]
        for path in ["world.hive.bees[]", "world.lastSwarm.queen", "world.lastSwarm.workers[]"] {
            groups[path] = bee
        }
        // An entity id is a one-key object, and it is the entity.
        for path in [
            "world.hive.bees[].id", "world.lastSwarm.queen.id", "world.lastSwarm.workers[].id",
            "world.hive.comb.queenCells[].id", "world.patches[].id", "world.attackHistory[].id"
        ] {
            groups[path] = ["rawValue"]
        }
        for path in ["world.hive.genetics", "world.lastSwarm.genetics"] {
            groups[path] = genetics
        }
        return groups
    }()

    /// `requiredGroups` flattened to one path per key.
    static let requiredKeys: Set<String> = Set(
        requiredGroups.flatMap { object, keys in
            keys.map { object.isEmpty ? $0 : "\(object).\($0)" }
        }
    )

    // MARK: - The save under test

    /// A colony a few days old, with one of everything a save can hold.
    ///
    /// Lived through rather than typed out where the engine will produce the
    /// thing in five days — brood, a history, a lineage, wild patches, the
    /// country — and placed by hand where it would not: a siege, a swarm on
    /// its way and one gone, a scouting party, a second queen, an almanac
    /// with a tally, a milestone. Placed values are ordinary values of their
    /// types; the point is that every type is present, so every key is.
    ///
    /// And that every field of `World` is off its default, so that a
    /// hand-written decoder that forgets a line — which decodes the default
    /// rather than failing — is caught by the round trip.
    static let colony: Simulation = {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity),
            startingAt: epoch,
            seed: 2_026_09_24
        )

        // A garden: a flower placed to species, one never identified, and
        // one somebody sent.
        simulation.registerPhotograph(
            photoLocalIdentifier: "photo-clover",
            species: FlowerCatalogue.whiteClover,
            confidence: 0.9,
            takenAt: epoch
        )
        simulation.registerPhotograph(
            photoLocalIdentifier: "photo-unknown",
            species: nil,
            confidence: 0,
            takenAt: epoch
        )
        _ = simulation.importSharedFlower(
            shareID: "share-1",
            photoLocalIdentifier: "photo-shared",
            species: FlowerCatalogue.heather,
            confidence: 0.7,
            takenAt: epoch,
            sharedBy: "A neighbour"
        )

        simulation.runDays(5)

        simulation.mutateWorld { world in
            let day = 5
            world.hive.comb.addQueenCell(QueenCell(
                id: EntityID(rawValue: 90_001), purpose: .supersedure, quality: 0.8
            ))
            world.hive.pathogens[.varroa] = 0.05
            if let index = world.hive.bees.firstIndex(where: { $0.kind == .worker && $0.isAdult }) {
                world.hive.bees[index].assignedJob = .foragingBee
            }

            world.recordAttack(AttackRecord(
                id: EntityID(rawValue: 90_002), predator: .skunk, day: 3,
                wasRepelled: true, beesLost: 2, storesLost: 1.5, combLost: 0
            ))
            world.activeThreat = ActiveThreat(predator: .skunk, beganOnDay: day, resolvesOnDay: day + 2)
            world.posture = .holdEntrance
            world.postureUntilDay = day + 2
            world.pendingSwarm = PendingSwarm(startedOnDay: day, departsOnDay: day + 8, discouraged: true)

            let queen = world.hive.bees.first { $0.kind == .queen }!
            let workers = Array(world.hive.bees.filter { $0.kind == .worker }.prefix(2))
            world.lastSwarm = DepartedSwarm(
                day: 2, queen: queen, workers: workers, genetics: world.hive.genetics,
                honeyCarried: 3, queenNumber: 1
            )
            world.scoutingParty = ScoutingParty(leftOnDay: day, returnsOnDay: day + 3)
            world.exploringToday = true
            world.entranceSealed = true
            world.entranceDecision = true
            world.honeyTaken = 4

            var lineage = world.lineage
            lineage.crown(onDay: 4, quality: 0.9)
            lineage.mated(onDay: 5, patrilines: 9)
            lineage.name(2, "Hazel")
            lineage.end(onDay: 5, .superseded)
            world.lineage = lineage

            var tally = YearTally(year: 1)
            tally.raids = 1
            tally.raidsRepelled = 1
            world.almanac = Almanac(
                entries: [AlmanacEntry(day: 3, season: .spring, kind: .threat, text: "A skunk.")],
                peakHoney: 40,
                tallies: [tally]
            )
            world.milestones = Milestones(achieved: [MilestoneRecord(milestone: .firstFlower, day: 0)])
        }

        return simulation
    }()

    /// Encoded as `GamePersistence` encodes it.
    static let save: Data = try! encoder().encode(colony)

    /// Every key in the save by path, with the way to one place it occurs.
    static let keys: [String: [Step]] = keyLocations(in: save)

    static let removableKeys: [String] = keys.keys.filter { !requiredKeys.contains($0) }.sorted()

    // MARK: - Fixtures

    static let fixturesDirectory: URL? = Bundle.module.url(
        forResource: "Fixtures", withExtension: nil
    )

    static let fixtureNames: [String] = {
        guard let directory = fixturesDirectory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }
        return names.filter { $0.hasPrefix("save-") && $0.hasSuffix(".json") }.sorted()
    }()

    // MARK: - Taking a key out

    /// One step into a JSON document.
    enum Step: Hashable, Sendable {
        case key(String)
        case index(Int)
    }

    /// The first place each key path occurs, so each is removed once rather
    /// than once for every bee.
    static func keyLocations(in data: Data) -> [String: [Step]] {
        var found: [String: [Step]] = [:]

        func walk(_ value: Any, path: String, steps: [Step]) {
            if let object = value as? [String: Any] {
                for key in object.keys.sorted() {
                    let childPath = path.isEmpty ? key : "\(path).\(key)"
                    let childSteps = steps + [.key(key)]
                    if found[childPath] == nil { found[childPath] = childSteps }
                    walk(object[key]!, path: childPath, steps: childSteps)
                }
            } else if let array = value as? [Any] {
                for (index, element) in array.enumerated() {
                    walk(element, path: "\(path)[]", steps: steps + [.index(index)])
                }
            }
        }

        walk(try! JSONSerialization.jsonObject(with: data), path: "", steps: [])
        return found
    }

    static func save(without path: String) throws -> Data {
        try save(of: colony, without: path)
    }

    static func save(of simulation: Simulation, without path: String) throws -> Data {
        let data = try encoder().encode(simulation)
        guard let steps = keyLocations(in: data)[path] else { throw NoSuchKey(path: path) }
        let document = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(withJSONObject: removing(steps[...], from: document))
    }

    struct NoSuchKey: Error, CustomStringConvertible {
        let path: String
        var description: String { "the save has no key at \(path)" }
    }

    static func removing(_ steps: ArraySlice<Step>, from value: Any) -> Any {
        guard let step = steps.first else { return value }
        switch step {
        case .key(let key):
            var object = value as! [String: Any]
            if steps.count == 1 {
                object.removeValue(forKey: key)
            } else {
                object[key] = removing(steps.dropFirst(), from: object[key]!)
            }
            return object
        case .index(let index):
            var array = value as! [Any]
            array[index] = removing(steps.dropFirst(), from: array[index])
            return array
        }
    }

    // MARK: - Coding as the game does

    /// The strategy `GamePersistence` and `SaveArchive` both use.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
