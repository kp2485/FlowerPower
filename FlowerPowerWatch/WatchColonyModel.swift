//
//  WatchColonyModel.swift
//  FlowerPower Watch
//
//  What the watch knows about the colony.
//
//  Three sources, in order of preference: a summary the phone just sent, the
//  watch's own copy of the save caught up to now, and nothing.
//
//  The middle one is the important one, and it used not to work. This model
//  and the complication both open `GamePersistence()` and expect to find the
//  phone's colony there, on the reasoning that the App Group is shared. It is
//  shared between processes on one device. It is not shared between devices,
//  so the watch was opening its own empty container every time, and the
//  complication — which has no other source at all — could never show
//  anything. The phone now sends the save across by file transfer and the
//  watch writes it into that container, which is what makes the fallback real.
//
//  Running the engine here is safe because it is deterministic: the watch
//  computes exactly the state the phone will compute, and is simply
//  overwritten next time they speak.
//

import Foundation
import Observation
import WatchConnectivity
import FlowerPowerCore
import FlowerPowerGame
import os

@Observable
@MainActor
final class WatchColonyModel: NSObject {

    private(set) var summary: WatchSummary?
    private(set) var lastUpdated: Date?

    /// Whether what is on screen was worked out here rather than sent by the
    /// phone. Not an error — the figure is usually right — but the watch
    /// should say so rather than imply it has just spoken to the phone.
    private(set) var isStale = false

    @ObservationIgnored private let decoder = JSONDecoder()
    @ObservationIgnored private let persistence = GamePersistence()
    @ObservationIgnored private let logger = Logger(
        subsystem: "com.kylepeterson.flowerpower.watch",
        category: "colony"
    )

    /// A summary older than this is shown with a caveat.
    private static let staleAfter: TimeInterval = 6 * 3600

    override init() {
        super.init()
        activateSession()
        loadFromSharedContainer()
    }

    // MARK: - Connectivity

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    fileprivate func apply(_ payload: [String: Any]) {
        guard let data = payload["summary"] as? Data else { return }

        do {
            let decoded = try decoder.decode(WatchSummary.self, from: data)
            summary = decoded
            lastUpdated = Date()
            isStale = false
        } catch {
            logger.error("could not decode watch summary: \(error.localizedDescription)")
        }
    }

    // MARK: - Fallback

    /// Reads the watch's copy of the save and catches the colony up locally.
    ///
    /// The phone is the authority — it is where photographs are taken and
    /// where the canonical save lives — but a watch that cannot reach it
    /// should still be honest rather than blank.
    func loadFromSharedContainer(force: Bool = false) {
        do {
            guard var simulation = try persistence.load() else { return }
            simulation.advance(to: Date())

            let computed = simulation.watchSummary()

            // Only fall back if there is nothing fresher, unless a save has
            // just arrived, in which case it is by definition the best thing
            // the watch has.
            let haveNothing = summary == nil
            let whatWeHaveIsOld = lastUpdated
                .map { Date().timeIntervalSince($0) > Self.staleAfter } ?? true

            guard force || haveNothing || whatWeHaveIsOld else { return }

            summary = computed
            lastUpdated = Date()
            // Computed here, not sent by the phone, so it is flagged as such.
            // `apply(_:)` clears it the moment the phone is heard from.
            isStale = true

        } catch {
            logger.error("could not read shared save: \(error.localizedDescription)")
        }
    }

    func refresh() {
        loadFromSharedContainer()

        guard WCSession.isSupported(), WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["request": "summary"], replyHandler: { [weak self] reply in
            Task { @MainActor in self?.apply(reply) }
        }, errorHandler: { [weak self] error in
            self?.logger.error("refresh failed: \(error.localizedDescription)")
        })
    }
}

// MARK: - WCSessionDelegate

extension WatchColonyModel: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in apply(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in apply(userInfo) }
    }

    /// The phone's copy of the colony.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Read synchronously, before returning: WatchConnectivity deletes the
        // inbox file as soon as this method does, so hopping to the main actor
        // first and reading there would usually find nothing.
        let data = try? Data(contentsOf: file.fileURL)
        Task { @MainActor in
            guard let data else { return }
            do {
                try GamePersistence().write(transferred: data)
                loadFromSharedContainer(force: true)
            } catch {
                logger.error("could not adopt phone save: \(error.localizedDescription)")
            }
        }
    }
}
