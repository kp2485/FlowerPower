import XCTest
import FlowerPowerCore
@testable import FlowerPowerGame

/// Flowers crossing between people.
///
/// Two halves worth testing for different reasons. The privacy half, because
/// a photograph's coordinate is where a person was standing and the failure
/// mode is telling a group chat where somebody lives. The untrusted-input
/// half, because a `.flower` file arrives from outside the app and nothing
/// about it is guaranteed.
final class FlowerShareTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private let image = Data(repeating: 0xFF, count: 2_048)

    private func share(
        speciesID: String? = "white_clover",
        confidence: Double = 0.9,
        latitude: Double? = nil,
        longitude: Double? = nil,
        sharedBy: String? = "Alex",
        note: String? = nil
    ) -> FlowerShare {
        FlowerShare(
            speciesID: speciesID,
            confidence: confidence,
            takenAt: epoch,
            sharedBy: sharedBy,
            note: note,
            latitude: latitude,
            longitude: longitude,
            imageData: image
        )
    }

    // MARK: - The file

    func testAShareRoundTrips() throws {
        let original = share()
        let restored = try FlowerShare.decoded(from: original.encoded())

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.speciesID, "white_clover")
        XCTAssertEqual(restored.confidence, 0.9, accuracy: 0.0001)
        XCTAssertEqual(restored.imageData, image)
        XCTAssertEqual(restored.sharedBy, "Alex")
    }

    func testRubbishIsNotAFlower() {
        XCTAssertThrowsError(
            try FlowerShare.decoded(from: Data("hello".utf8))
        ) { error in
            XCTAssertEqual(error as? FlowerShareError, .notAFlowerFile)
        }
    }

    func testAShareFromANewerVersionIsRefusedReadably() throws {
        var future = share()
        future.version = FlowerShare.currentVersion + 1

        XCTAssertThrowsError(try FlowerShare.decoded(from: future.encoded())) { error in
            XCTAssertEqual(
                error as? FlowerShareError,
                .fromANewerVersion(FlowerShare.currentVersion + 1)
            )
        }
    }

    func testAShareWithNoPhotographIsRefused() throws {
        var empty = share()
        empty.imageData = Data()

        XCTAssertThrowsError(try FlowerShare.decoded(from: empty.encoded())) { error in
            XCTAssertEqual(error as? FlowerShareError, .noImage)
        }
    }

    func testAnAbsurdlyLargePhotographIsRefused() throws {
        var huge = share()
        huge.imageData = Data(repeating: 0, count: FlowerShare.maximumImageBytes + 1)

        XCTAssertThrowsError(try FlowerShare.decoded(from: huge.encoded()))
    }

    // MARK: - Location

    /// The default, and the one that matters most.
    func testLocationIsNotSharedUnlessAsked() {
        let point = GeoPoint(latitude: 51.507_351, longitude: -0.127_758)
        XCTAssertNil(LocationSharing.none.apply(to: point))
    }

    func testApproximateLocationIsRoundedToAboutAKilometre() throws {
        let home = GeoPoint(latitude: 51.507_351, longitude: -0.127_758)
        let rounded = try XCTUnwrap(LocationSharing.approximate.apply(to: home))

        XCTAssertNotEqual(rounded.latitude, home.latitude)
        XCTAssertEqual(rounded.latitude, 51.51, accuracy: 0.0001)
        XCTAssertEqual(rounded.longitude, -0.13, accuracy: 0.0001)

        // Roughly a kilometre of slop, and never more than a couple.
        XCTAssertLessThan(rounded.distance(to: home), 2_000)
    }

    /// Two photographs taken in the same street must round to the same point,
    /// or the rounding tells you more than it appears to.
    func testNearbyPointsRoundTogether() throws {
        let first = try XCTUnwrap(LocationSharing.approximate.apply(
            to: GeoPoint(latitude: 51.5071, longitude: -0.1277)
        ))
        let second = try XCTUnwrap(LocationSharing.approximate.apply(
            to: GeoPoint(latitude: 51.5073, longitude: -0.1279)
        ))
        XCTAssertEqual(first, second)
    }

    func testExactLocationIsPassedThroughUnchanged() {
        let point = GeoPoint(latitude: 51.507_351, longitude: -0.127_758)
        XCTAssertEqual(LocationSharing.exact.apply(to: point), point)
    }

    func testNoLocationToShareStaysNoLocation() {
        for setting in LocationSharing.allCases {
            XCTAssertNil(setting.apply(to: nil))
        }
    }

    // MARK: - Untrusted input

    func testConfidenceIsClamped() {
        XCTAssertEqual(share(confidence: 1_000_000).validated().confidence, 1)
        XCTAssertEqual(share(confidence: -5).validated().confidence, 0)
    }

    /// A value that is not a number at all is treated as no confidence rather
    /// than clamped to full. Confidence scales the patch's yield, so the safe
    /// reading of a nonsense value is "we do not know what this is", which is
    /// exactly what zero means — and a share built to be hostile should not be
    /// able to ask for the maximum by sending infinity.
    func testAConfidenceThatIsNotANumberIsTreatedAsNone() {
        XCTAssertEqual(share(confidence: .nan).validated().confidence, 0)
        XCTAssertEqual(share(confidence: .infinity).validated().confidence, 0)
        XCTAssertEqual(share(confidence: -.infinity).validated().confidence, 0)
    }

    /// A species the recipient does not have is not an error. Their bees work
    /// an unnamed flower perfectly well, which is the whole design of
    /// identification being a bonus.
    func testAnUnknownSpeciesBecomesAnUnidentifiedFlower() {
        let validated = share(speciesID: "triffid").validated()

        XCTAssertNil(validated.speciesID)
        XCTAssertNil(validated.species)
        XCTAssertEqual(validated.displayName, "An unidentified flower")
    }

    func testACoordinateOffTheGlobeIsDropped() {
        XCTAssertNil(share(latitude: 999, longitude: 0).validated().coordinate)
        XCTAssertNil(share(latitude: 0, longitude: 500).validated().coordinate)
        XCTAssertNil(share(latitude: .nan, longitude: .nan).validated().coordinate)
    }

    func testHalfACoordinateIsNoCoordinate() {
        XCTAssertNil(share(latitude: 51.5, longitude: nil).validated().coordinate)
    }

    /// Text from another person lands in a label. It should not be able to
    /// arrive a thousand characters long or full of newlines.
    func testDisplayTextIsTamed() {
        let shouty = share(sharedBy: String(repeating: "a", count: 500)).validated()
        XCTAssertEqual(shouty.sharedBy?.count, 80)

        let multiline = share(sharedBy: "Alex\n\nfrom\nthe\nallotment").validated()
        XCTAssertFalse(multiline.sharedBy?.contains("\n") ?? true)

        XCTAssertNil(share(sharedBy: "   ").validated().sharedBy)
    }

    func testAShareFromTheFutureIsBroughtBackToNow() {
        let future = FlowerShare(
            speciesID: "white_clover",
            confidence: 0.5,
            takenAt: Date().addingTimeInterval(60 * 60 * 24 * 365),
            sharedBy: nil,
            imageData: image
        )
        XCTAssertLessThanOrEqual(future.validated().takenAt, Date().addingTimeInterval(60))
    }

    func testAShareWithNoIdentifierGetsOne() {
        var anonymous = share()
        anonymous.id = "  "
        XCTAssertFalse(anonymous.validated().id.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    // MARK: - Identifiers

    func testASharedFlowerIsDistinguishableFromTheOwnersOwnPhotos() {
        let received = share()
        XCTAssertTrue(FlowerShare.isSharedIdentifier(received.localIdentifier))
        XCTAssertFalse(FlowerShare.isSharedIdentifier("B84E8479-475C-4727-A4A4-B77AA9980D19/L0/001"))
    }
}
