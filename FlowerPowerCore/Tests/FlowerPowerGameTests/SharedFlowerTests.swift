import XCTest
import FlowerPowerCore
@testable import FlowerPowerGame

/// Sending a flower to somebody, and taking one in.
@MainActor
final class SharedFlowerTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private let image = Data(repeating: 0xFF, count: 1_024)

    private func makeStore(
        persistence: GamePersisting = InMemoryPersistence()
    ) -> GameStore {
        GameStore(
            simulation: Simulation.newGame(
                at: HiveLocation(
                    coordinate: GeoPoint(latitude: 51.5072, longitude: -0.1276),
                    type: .livingTreeCavity
                ),
                startingAt: epoch,
                seed: 77
            ),
            persistence: persistence,
            clock: { self.epoch }
        )
    }

    private func incoming(
        id: String = UUID().uuidString,
        speciesID: String? = "white_clover",
        latitude: Double? = nil,
        longitude: Double? = nil
    ) -> FlowerShare {
        FlowerShare(
            id: id,
            speciesID: speciesID,
            confidence: 0.9,
            takenAt: epoch,
            sharedBy: "Alex",
            latitude: latitude,
            longitude: longitude,
            imageData: image
        )
    }

    // MARK: - Receiving

    func testImportingAFlowerAddsAPatch() async throws {
        let store = makeStore()
        let outcome = store.importShared(incoming())

        guard case .added(let id) = outcome else {
            return XCTFail("expected the flower to be added, got \(outcome)")
        }

        let patch = try XCTUnwrap(store.snapshot.patches.first { $0.id == id })
        XCTAssertTrue(patch.isShared)
        XCTAssertEqual(patch.sharedBy, "Alex")
        XCTAssertEqual(patch.speciesName, "White Clover")
    }

    /// A share lives in a message thread and stays tappable for ever.
    func testTheSameFlowerCannotBeImportedTwice() async {
        let store = makeStore()
        let share = incoming()

        XCTAssertEqual(store.importShared(share), .added(store.snapshot.patches[0].id))
        XCTAssertEqual(store.importShared(share), .alreadyHave)
        XCTAssertEqual(store.snapshot.patches.count, 1)
    }

    func testTwoPeopleSharingTheSameFlowerAreTwoGifts() async {
        let store = makeStore()
        store.importShared(incoming(id: "one"))
        store.importShared(incoming(id: "two"))

        XCTAssertEqual(store.snapshot.patches.count, 2)
    }

    func testImportingSurvivesARestart() async throws {
        let persistence = InMemoryPersistence()
        let store = makeStore(persistence: persistence)
        let share = incoming(id: "gift")
        store.importShared(share)

        let reloaded = GameStore.load(persistence: persistence, clock: { self.epoch })

        XCTAssertEqual(reloaded.snapshot.patches.count, 1)
        XCTAssertEqual(
            reloaded.importShared(share), .alreadyHave,
            "the record of what has been taken in has to be part of the save, "
            + "or every relaunch reopens the door"
        )
    }

    /// A gift is worth what the thing is worth.
    ///
    /// This asserted the opposite for about an hour. A shared flower was
    /// deliberately worth 70% of one the player found, to stop a
    /// well-connected player skipping the core loop — and then the measurement
    /// showed a colony fed entirely on shared flowers survives just as well at
    /// any yield down to 0.5, because survival is bounded by comb space rather
    /// than by forage. The penalty did not do its job, and all it achieved was
    /// making somebody's present arrive diminished.
    func testASharedFlowerIsWorthTheSameAsOneYouFound() async throws {
        let store = makeStore()

        let mine = store.recordPhotograph(
            localIdentifier: "mine",
            species: FlowerCatalogue.species(withID: "white_clover"),
            confidence: 0.9,
            coordinate: nil,
            takenAt: epoch
        )
        store.importShared(incoming(id: "theirs"))

        let ours = store.simulationForTransfer.patches
        let found = try XCTUnwrap(ours.first { $0.id == mine })
        let given = try XCTUnwrap(ours.first(where: \.isShared))

        XCTAssertEqual(
            given.nectarCapacity, found.nectarCapacity, accuracy: 0.001,
            "the same species photographed by a friend is the same flower"
        )
        XCTAssertEqual(
            given.pollenCapacity, found.pollenCapacity, accuracy: 0.001
        )
    }

    func testAnUnidentifiedSharedFlowerStillFeedsTheBees() async throws {
        let store = makeStore()
        store.importShared(incoming(speciesID: nil))

        let patch = try XCTUnwrap(store.snapshot.patches.first)
        XCTAssertFalse(patch.isIdentified)
        XCTAssertGreaterThan(
            store.simulationForTransfer.patches[0].nectarCapacity, 0,
            "an unnamed flower is still forage"
        )
    }

    /// Without a coordinate the bees fly a nominal distance rather than
    /// refusing to work it, which is what keeps location optional everywhere.
    func testAFlowerSharedWithoutALocationIsStillWorkable() async throws {
        let store = makeStore()
        store.importShared(incoming())

        let patch = try XCTUnwrap(store.snapshot.patches.first)
        XCTAssertNil(patch.coordinate)
        XCTAssertTrue(patch.isWithinRange)
        XCTAssertEqual(patch.distanceMetres, FlowerPatch.nominalDistance, accuracy: 1)
    }

    func testAFlowerSharedWithALocationIsPlacedRelativeToYourOwnHive() async throws {
        let store = makeStore()
        // About a kilometre north of the hive.
        store.importShared(incoming(latitude: 51.5162, longitude: -0.1276))

        let patch = try XCTUnwrap(store.snapshot.patches.first)
        XCTAssertNotNil(patch.coordinate)
        XCTAssertEqual(patch.distanceMetres, 1_000, accuracy: 200)
    }

    // MARK: - Sending

    func testSharingAPatchDoesNotIncludeLocationByDefault() async throws {
        let store = makeStore()
        let id = store.recordPhotograph(
            localIdentifier: "mine",
            species: FlowerCatalogue.species(withID: "heather"),
            confidence: 0.8,
            coordinate: GeoPoint(latitude: 51.507_351, longitude: -0.127_758),
            takenAt: epoch
        )

        let share = try XCTUnwrap(store.share(patch: id, imageData: image, from: "Kyle"))

        XCTAssertNil(
            share.coordinate,
            "a photograph's coordinate is where a person was standing; it does "
            + "not travel unless they ask for it"
        )
        XCTAssertEqual(share.speciesID, "heather")
        XCTAssertEqual(share.sharedBy, "Kyle")
    }

    func testSharingCanIncludeAnApproximateLocation() async throws {
        let store = makeStore()
        let exact = GeoPoint(latitude: 51.507_351, longitude: -0.127_758)
        let id = store.recordPhotograph(
            localIdentifier: "mine", species: nil, confidence: 0,
            coordinate: exact, takenAt: epoch
        )

        let share = try XCTUnwrap(store.share(
            patch: id, imageData: image, from: "Kyle", location: .approximate
        ))
        let sent = try XCTUnwrap(share.coordinate)

        XCTAssertNotEqual(sent, exact)
        XCTAssertLessThan(sent.distance(to: exact), 2_000)
    }

    func testSharingAPatchThatIsNotThereGivesNothing() async {
        let store = makeStore()
        XCTAssertNil(store.share(
            patch: EntityID(rawValue: 999_999), imageData: image, from: "Kyle"
        ))
    }

    /// Round trip between two players, through the file that actually crosses.
    func testAFlowerSurvivesTheJourneyBetweenTwoPlayers() async throws {
        let sender = makeStore()
        let id = sender.recordPhotograph(
            localIdentifier: "mine",
            species: FlowerCatalogue.species(withID: "bramble"),
            confidence: 0.75,
            coordinate: nil,
            takenAt: epoch
        )

        let share = try XCTUnwrap(sender.share(patch: id, imageData: image, from: "Kyle"))
        let file = try share.encoded()

        let recipient = makeStore()
        let received = try FlowerShare.decoded(from: file)
        guard case .added(let newID) = recipient.importShared(received) else {
            return XCTFail("the flower did not arrive")
        }

        let patch = try XCTUnwrap(recipient.snapshot.patches.first { $0.id == newID })
        XCTAssertEqual(patch.speciesName, "Bramble")
        XCTAssertEqual(patch.sharedBy, "Kyle")
        XCTAssertTrue(patch.isShared)
    }
}
