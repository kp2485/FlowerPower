import XCTest
import FlowerPowerCore
@testable import FlowerPowerGame

/// Flowers crossing between people.
///
/// Worth testing because a `.flower` file arrives from outside the app and
/// nothing about it is guaranteed: it may be truncated, hand-edited, or built
/// to be hostile.
final class FlowerShareTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private let image = Data(repeating: 0xFF, count: 2_048)

    private func share(
        speciesID: String? = "white_clover",
        confidence: Double = 0.9,
        sharedBy: String? = "Alex",
        note: String? = nil
    ) -> FlowerShare {
        FlowerShare(
            speciesID: speciesID,
            confidence: confidence,
            takenAt: epoch,
            sharedBy: sharedBy,
            note: note,
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

    /// A `.flower` file sits in a message thread for ever, so one written by a
    /// build that carried `latitude` and `longitude` will still be tapped years
    /// from now. It must open, and open as the flower it is. The format version
    /// is deliberately not bumped for this: the synthesised decoder ignores keys
    /// it does not know, so a flower from either build reads in the other, and
    /// refusing it over a field nobody needs would throw away a gift.
    func testAShareCarryingTheOldLocationKeysStillOpens() throws {
        let fixture = """
        {
          "version": 1,
          "id": "0F1B7C1E-0000-0000-0000-00000000ABCD",
          "speciesID": "white_clover",
          "confidence": 0.9,
          "takenAt": "2023-11-14T22:13:20Z",
          "sharedBy": "Alex",
          "latitude": 51.507351,
          "longitude": -0.127758,
          "imageData": "\(image.base64EncodedString())"
        }
        """

        let restored = try FlowerShare.decoded(from: Data(fixture.utf8))

        XCTAssertEqual(restored.id, "0F1B7C1E-0000-0000-0000-00000000ABCD")
        XCTAssertEqual(restored.speciesID, "white_clover")
        XCTAssertEqual(restored.sharedBy, "Alex")
        XCTAssertEqual(restored.imageData, image)
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
