import Testing
import Foundation
@testable import FlowerPowerCore

/// The watch's readings are the phone's overview, line for line.
@Suite("Watch readings")
struct WatchReadingsTests {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func simulation() -> Simulation {
        var simulation = Simulation.newGame(
            at: HiveLocation(type: .livingTreeCavity),
            startingAt: epoch,
            seed: 21
        )
        for _ in 0..<40 { _ = simulation.stepDay() }
        return simulation
    }

    @Test("The summary carries every reading the overview shows, in its order")
    func readingsMatchTheOverview() {
        let simulation = simulation()
        let summary = simulation.watchSummary(now: epoch)
        let overview = DashboardSummary(snapshot: simulation.snapshot(), history: simulation.history)

        #expect(summary.readings.map(\.kind) == overview.tiles.map(\.kind.rawValue))
        for (reading, tile) in zip(summary.readings, overview.tiles) {
            #expect(reading.headline == tile.headline)
            #expect(reading.severity == tile.severity)
            #expect(reading.symbolName == tile.symbolName)
            #expect(!reading.spoken.isEmpty)
        }
    }

    @Test("A summary from a phone with no readings decodes with none")
    func olderSummaryDecodes() throws {
        let summary = simulation().watchSummary(now: epoch)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try #require(
            try JSONSerialization.jsonObject(with: encoder.encode(summary)) as? [String: Any]
        )
        object["readings"] = nil
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WatchSummary.self, from: data)

        #expect(decoded.readings.isEmpty)
        #expect(decoded.status == summary.status)
    }

    @Test("Readings survive the trip to the watch")
    func readingsRoundTrip() throws {
        let summary = simulation().watchSummary(now: epoch)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WatchSummary.self, from: encoder.encode(summary))
        #expect(decoded.readings == summary.readings)
        #expect(!decoded.readings.isEmpty)
    }
}
