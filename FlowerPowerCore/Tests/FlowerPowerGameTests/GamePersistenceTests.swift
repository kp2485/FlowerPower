import XCTest
import FlowerPowerCore
@testable import FlowerPowerGame

/// The save file.
///
/// The load-bearing claim is that a save round-trips *exactly*: the colony that
/// comes back must go on to behave identically to the one that was saved. The
/// whole offline-catch-up design rests on it, and JSON is lossy about doubles
/// if anyone reaches for a lossy encoder.
final class GamePersistenceTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flowerpower-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let directory, FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func makeSimulation(days: Int = 30, seed: UInt64 = 4242) -> Simulation {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity),
            startingAt: Date(timeIntervalSince1970: 1_700_000_000),
            seed: seed
        )
        simulation.registerPhotograph(
            photoLocalIdentifier: "p1",
            species: FlowerCatalogue.all.first,
            confidence: 0.8,
            takenAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        for _ in 0..<days { _ = simulation.stepDay() }
        return simulation
    }

    func testNothingIsLoadedBeforeAnythingIsSaved() throws {
        let persistence = GamePersistence(directory: directory)
        XCTAssertNil(try persistence.load())
    }

    func testSaveAndLoadRoundTrips() throws {
        let persistence = GamePersistence(directory: directory)
        let original = makeSimulation()

        try persistence.save(original)
        let restored = try XCTUnwrap(try persistence.load())

        XCTAssertEqual(restored, original)
    }

    /// The one that matters. Equality after a reload is not enough — the
    /// random stream and the id generator have to come back too, or the
    /// restored colony diverges the moment it is stepped.
    func testARestoredColonyBehavesIdenticallyToOneThatWasNeverSaved() throws {
        let persistence = GamePersistence(directory: directory)
        var live = makeSimulation()
        try persistence.save(live)

        var restored = try XCTUnwrap(try persistence.load())

        for _ in 0..<60 {
            _ = live.stepDay()
            _ = restored.stepDay()
        }

        XCTAssertEqual(
            restored, live,
            "a reloaded colony must go on to do exactly what the live one did"
        )
    }

    func testClearRemovesTheSave() throws {
        let persistence = GamePersistence(directory: directory)
        try persistence.save(makeSimulation(days: 2))
        XCTAssertNotNil(try persistence.load())

        try persistence.clear()
        XCTAssertNil(try persistence.load())
    }

    func testClearingNothingIsNotAnError() throws {
        let persistence = GamePersistence(directory: directory)
        XCTAssertNoThrow(try persistence.clear())
    }

    /// The directory may not exist yet on a first run.
    func testSavingCreatesTheDirectory() throws {
        let nested = directory.appendingPathComponent("does/not/exist/yet")
        let persistence = GamePersistence(directory: nested)

        try persistence.save(makeSimulation(days: 1))
        XCTAssertNotNil(try persistence.load())
    }

    // MARK: - Saves written by an older build

    /// A colony saved when patches and the nest carried a coordinate must open.
    ///
    /// This is the one failure mode that cannot be apologised for: `GameStore`
    /// treats an unreadable save as no save, so a decode error here would
    /// silently delete somebody's colony. Swift's synthesised decoder ignores
    /// keys it does not recognise, which is what makes dropping an optional
    /// field safe — and this is the test that says so rather than a comment
    /// claiming it.
    ///
    /// The fixture is built from a live colony and then salted with the keys an
    /// older build wrote, so it stays a real save rather than a hand-typed one
    /// that drifts out of date.
    func testASaveWrittenWhenFlowersCarriedCoordinatesStillOpens() throws {
        let original = makeSimulation(days: 5)
        let json = try JSONSerialization.jsonObject(
            with: GamePersistence.encodeForTransfer(original)
        )
        var document = try XCTUnwrap(json as? [String: Any])
        var world = try XCTUnwrap(document["world"] as? [String: Any])
        var hive = try XCTUnwrap(world["hive"] as? [String: Any])
        var location = try XCTUnwrap(hive["location"] as? [String: Any])
        let point: [String: Any] = ["latitude": 51.5072, "longitude": -0.1276]

        location["coordinate"] = point
        hive["location"] = location
        world["hive"] = hive
        world["patches"] = try XCTUnwrap(world["patches"] as? [[String: Any]]).map {
            var patch = $0
            patch["coordinate"] = point
            return patch
        }
        document["world"] = world

        let older = try JSONSerialization.data(withJSONObject: document)
        let restored = try GamePersistence.decodeTransfer(older)

        XCTAssertEqual(
            restored, original,
            "a coordinate nothing reads any more must be ignored, not fatal"
        )
        XCTAssertEqual(restored.patches.count, original.patches.count)
        XCTAssertEqual(
            restored.patches.first?.distanceMetres,
            original.patches.first?.distanceMetres,
            "the distance the bees fly comes from the patch, not from a key that is gone"
        )
    }

    // MARK: - Saves written before the world existed

    /// A colony saved before there was any country around it must open, and
    /// must be given one on the way through.
    ///
    /// Built the same way as the test above — a live colony, with the key an
    /// older build did not write taken back out — so it stays a real save
    /// rather than a hand-typed one that drifts. What it proves is the thing
    /// `WORLD.md` section 9 promises: no old save fails, and the flowers in it
    /// end up in the garden.
    func testASaveWrittenBeforeTheWorldOpensAndIsGivenOne() throws {
        let original = makeSimulation(days: 5)
        let json = try JSONSerialization.jsonObject(
            with: GamePersistence.encodeForTransfer(original)
        )
        var document = try XCTUnwrap(json as? [String: Any])
        var world = try XCTUnwrap(document["world"] as? [String: Any])

        world.removeValue(forKey: "terrain")
        world["patches"] = try XCTUnwrap(world["patches"] as? [[String: Any]]).map {
            var patch = $0
            patch.removeValue(forKey: "cell")
            // Where every flower in the game stood before there was anywhere
            // for it to be.
            patch["distanceMetres"] = FlowerPatch.nominalDistance
            return patch
        }
        document["world"] = world

        let older = try JSONSerialization.data(withJSONObject: document)

        // Decoded raw, it is a colony with no world at all — which is what
        // makes the migration below a migration rather than a no-op.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let raw = try decoder.decode(Simulation.self, from: older)
        XCTAssertNil(raw.terrain)
        XCTAssertNil(raw.patches.first?.cell)

        let restored = try GamePersistence.decodeTransfer(older)

        XCTAssertNotNil(restored.terrain, "an old save was not given a world")
        XCTAssertEqual(restored.terrain?.gardenRings, 1)
        XCTAssertEqual(
            restored.patches.first?.cell,
            HexCoordinate.origin.ring(radius: 1).first,
            "the flowers should have been planted, innermost first"
        )
        XCTAssertEqual(
            restored.patches.first?.distanceMetres, 200,
            "a garden is next to the nest; that is the point of it"
        )
    }

    /// Reading the same old save twice must give the same country both times,
    /// or the widget and the app would disagree about where the colony lives.
    func testMigrationIsDeterministic() throws {
        let original = makeSimulation(days: 5)
        let json = try JSONSerialization.jsonObject(
            with: GamePersistence.encodeForTransfer(original)
        )
        var document = try XCTUnwrap(json as? [String: Any])
        var world = try XCTUnwrap(document["world"] as? [String: Any])
        world.removeValue(forKey: "terrain")
        document["world"] = world
        let older = try JSONSerialization.data(withJSONObject: document)

        let first = try GamePersistence.decodeTransfer(older)
        let second = try GamePersistence.decodeTransfer(older)
        XCTAssertEqual(first, second)
        XCTAssertNotNil(first.terrain?.seed)

        // And a different colony gets a different countryside, or every old
        // save in the world would open onto the same village.
        let otherOriginal = makeSimulation(days: 5, seed: 77)
        let otherJSON = try JSONSerialization.jsonObject(
            with: GamePersistence.encodeForTransfer(otherOriginal)
        )
        var otherDocument = try XCTUnwrap(otherJSON as? [String: Any])
        var otherWorld = try XCTUnwrap(otherDocument["world"] as? [String: Any])
        otherWorld.removeValue(forKey: "terrain")
        otherDocument["world"] = otherWorld
        let otherOlder = try JSONSerialization.data(withJSONObject: otherDocument)

        XCTAssertNotEqual(
            first.terrain?.seed,
            try GamePersistence.decodeTransfer(otherOlder).terrain?.seed
        )
    }

    /// A colony that already has a world is left exactly as it was.
    func testMigrationLeavesAColonyThatHasAWorldAlone() throws {
        let original = makeSimulation(days: 3)
        let restored = try GamePersistence.decodeTransfer(
            GamePersistence.encodeForTransfer(original)
        )
        XCTAssertEqual(restored, original)
    }

    // MARK: - Crossing between devices

    func testTransferBytesRoundTrip() throws {
        let original = makeSimulation()
        let data = try GamePersistence.encodeForTransfer(original)
        XCTAssertEqual(try GamePersistence.decodeTransfer(data), original)
    }

    /// The watch writes whatever the phone sends straight to its own save file.
    /// A truncated or garbled transfer must not destroy the colony already
    /// there, so the payload is decoded before anything is written.
    func testACorruptTransferDoesNotOverwriteAGoodSave() throws {
        let persistence = GamePersistence(directory: directory)
        let good = makeSimulation()
        try persistence.save(good)

        let rubbish = Data("this is not a colony".utf8)
        XCTAssertThrowsError(try persistence.write(transferred: rubbish))

        XCTAssertEqual(
            try persistence.load(), good,
            "the existing save must survive a bad transfer"
        )
    }

    func testAValidTransferReplacesTheSave() throws {
        let persistence = GamePersistence(directory: directory)
        try persistence.save(makeSimulation(days: 5, seed: 1))

        let newer = makeSimulation(days: 90, seed: 2)
        try persistence.write(transferred: GamePersistence.encodeForTransfer(newer))

        XCTAssertEqual(try persistence.load(), newer)
    }

    // MARK: - In-memory double

    func testInMemoryPersistenceCountsSaves() throws {
        let persistence = InMemoryPersistence()
        XCTAssertEqual(persistence.saveCount, 0)

        try persistence.save(makeSimulation(days: 1))
        try persistence.save(makeSimulation(days: 2))

        XCTAssertEqual(persistence.saveCount, 2)
    }
}
