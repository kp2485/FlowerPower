//
//  WatchColonyModel.swift
//  FlowerPower Watch
//
//  Holds the colony summary the phone sends, and falls back to reading the
//  shared save file directly when the phone has not been in touch.
//
//  The fallback matters. A watch out of range of its phone should still show
//  something true rather than a spinner — and because the engine is portable
//  and deterministic, the watch can open the same save file and catch the
//  colony up itself to work out what the state must be by now.
//

import Foundation
import Observation
import WatchConnectivity
import FlowerPowerCore
import os

@Observable
@MainActor
final class WatchColonyModel: NSObject {

    private(set) var summary: WatchSummary?
    private(set) var lastUpdated: Date?
    private(set) var isStale = false

    @ObservationIgnored private let decoder = JSONDecoder()
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

    /// Reads the shared save and catches the colony up locally.
    ///
    /// The phone is the authority — it is where photographs are taken and where
    /// the canonical save lives — but a watch that cannot reach it should still
    /// be honest rather than blank. Running the engine here is safe precisely
    /// because it is deterministic: the watch computes the same state the phone
    /// will, and is simply overwritten next time they speak.
    func loadFromSharedContainer() {
        do {
            guard var simulation = try GamePersistence().load() else { return }
            simulation.advance(to: Date())

            let computed = simulation.watchSummary()
            // Only fall back if we have nothing fresher.
            if summary == nil || (lastUpdated.map { Date().timeIntervalSince($0) > Self.staleAfter } ?? true) {
                summary = computed
                lastUpdated = Date()
                // This is the fallback path: the figure was computed here, not
                // sent by the phone, so it is flagged as such. `apply(_:)`
                // clears it the moment the phone is heard from.
                isStale = true
            }
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
}
