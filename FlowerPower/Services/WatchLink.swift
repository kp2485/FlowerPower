//
//  WatchLink.swift
//  FlowerPower
//
//  Keeps the watch's picture of the colony current.
//
//  The watch does not run the simulation. It could — the engine is portable and
//  deterministic — but it has no camera, no map and no reason to, and running
//  two copies means two save files that can disagree. So the phone simulates and
//  sends a small summary, and the watch renders it.
//
//  `transferCurrentComplicationUserInfo` is used rather than `sendMessage`
//  because it works when the watch app is not running, which is when a
//  complication most needs updating.
//

import Foundation
import WatchConnectivity
import FlowerPowerCore
import os

final class WatchLink: NSObject, WCSessionDelegate {

    private let logger = Logger(subsystem: "com.kylepeterson.flowerpower", category: "watch")
    private let encoder = JSONEncoder()

    /// Throttles updates: the colony ticks hourly in simulated time, but the
    /// complication budget is small and there is no point spending it on a
    /// change of two bees.
    private var lastSent: Date?
    private var lastSentSummary: WatchSummary?
    private static let minimumInterval: TimeInterval = 15 * 60

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ summary: WatchSummary, force: Bool = false) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        guard force || shouldSend(summary) else { return }

        do {
            let payload = ["summary": try encoder.encode(summary)]

            // Urgent news jumps the queue; routine updates ride the
            // complication transfer, which survives the app not running.
            if summary.status == .critical || summary.topAlert?.severity == .critical {
                if session.isReachable {
                    session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                        self?.logger.error("watch message failed: \(error.localizedDescription)")
                    }
                    lastSent = Date()
                    lastSentSummary = summary
                    return
                }
            }

            session.transferCurrentComplicationUserInfo(payload)
            lastSent = Date()
            lastSentSummary = summary

        } catch {
            logger.error("could not encode watch summary: \(error.localizedDescription)")
        }
    }

    /// Send when something a glance would notice has changed, or when enough
    /// time has passed to be worth refreshing anyway.
    private func shouldSend(_ summary: WatchSummary) -> Bool {
        guard let lastSentSummary, let lastSent else { return true }

        if summary.status != lastSentSummary.status { return true }
        if summary.topAlert?.kind != lastSentSummary.topAlert?.kind { return true }
        if summary.season != lastSentSummary.season { return true }
        if summary.shortHeadline != lastSentSummary.shortHeadline { return true }

        return Date().timeIntervalSince(lastSent) >= Self.minimumInterval
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            logger.error("watch session activation failed: \(error.localizedDescription)")
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate so a newly paired watch is picked up.
        WCSession.default.activate()
    }
    #endif
}
