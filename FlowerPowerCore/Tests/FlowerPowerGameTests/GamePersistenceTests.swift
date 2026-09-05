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
            at: HiveLocation(
                coordinate: GeoPoint(latitude: 51.5072, longitude: -0.1276),
                type: .livingTreeCavity
            ),
            startingAt: Date(timeIntervalSince1970: 1_700_000_000),
            seed: seed
        )
        simulation.registerPhotograph(
            photoLocalIdentifier: "p1",
            species: FlowerCatalogue.all.first,
            confidence: 0.8,
            coordinate: GeoPoint(latitude: 51.51, longitude: -0.12),
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
