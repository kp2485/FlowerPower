//
//  WatchLink.swift
//  FlowerPower
//
//  Getting the colony onto the wrist.
//
//  The watch does not run the game. It could — the engine is portable and
//  deterministic — but it has no camera, no map and no reason to, and two
//  running copies means two save files that can disagree. So the phone
//  simulates and the watch renders.
//
//  What is sent, and why it is two things
//
//  A **summary** goes on every meaningful change. It is small, and
//  `transferCurrentComplicationUserInfo` is the one channel with a budget
//  reserved for keeping a complication current, including when the watch app
//  is not running.
//
//  The **whole save** goes across too, much less often, by file transfer. This
//  is the part that was missing, and its absence was a real bug rather than a
//  gap. `WatchColonyModel` and the complication's timeline provider both open
//  `GamePersistence()` expecting the phone's `colony.json`, on the reasoning
//  that an App Group is shared. An App Group is shared between processes on
//  one device; it is not shared between devices. The watch was opening its own
//  empty container, finding nothing, and falling back to a spinner — and the
//  complication, which has no other source, could never show anything at all.
//
//  With the file across, the watch has a real colony and can catch it up
//  itself between transfers. That is safe precisely because the engine is
//  deterministic: the watch computes exactly what the phone will, and is
//  overwritten next time they speak.
//

import Foundation
import WatchConnectivity
import FlowerPowerCore
import FlowerPowerGame
import os

final class WatchLink: NSObject, WCSessionDelegate {

    private let logger = Logger(subsystem: "com.kylepeterson.flowerpower", category: "watch")
    private let encoder = JSONEncoder()

    /// Throttles summaries: the colony ticks hourly in simulated time, but the
    /// complication budget is small and there is no point spending it on a
    /// change of two bees.
    private var lastSent: Date?
    private var lastSentSummary: WatchSummary?
    private static let minimumInterval: TimeInterval = 15 * 60

    /// Throttles the save file, which is orders of magnitude bigger than a
    /// summary and only needs to be fresh enough for the watch to catch up
    /// from when it is out of touch.
    private var lastFileSent: Date?
    private static let minimumFileInterval: TimeInterval = 4 * 3600

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Sending

    /// Sends the summary, and the save file when it is due.
    func send(_ simulation: Simulation, summary: WatchSummary, force: Bool = false) {
        send(summary, force: force)
        sendSaveFile(simulation, force: force)
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

    /// Writes the save to a temporary file and hands it to WatchConnectivity.
    ///
    /// `transferFile` rather than `transferUserInfo` because a mature colony
    /// is several hundred kilobytes of bees, comfortably past what a user-info
    /// dictionary will carry. The system delivers it in the background and
    /// retries on its own, so there is nothing to wait for here.
    private func sendSaveFile(_ simulation: Simulation, force: Bool) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired,
              session.isWatchAppInstalled else { return }

        if !force, let lastFileSent,
           Date().timeIntervalSince(lastFileSent) < Self.minimumFileInterval {
            return
        }

        do {
            let data = try GamePersistence.encodeForTransfer(simulation)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("colony-transfer.json")
            try data.write(to: url, options: .atomic)

            session.transferFile(url, metadata: ["kind": "save"])
            lastFileSent = Date()

        } catch {
            logger.error("could not send save to watch: \(error.localizedDescription)")
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

    /// The watch asking for a fresh copy, which it does when it opens and finds
    /// what it has is stale.
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard message["request"] as? String == "summary" else {
            replyHandler([:])
            return
        }

        // Read the save rather than reaching for the store: this arrives on a
        // background queue, and the store is main-actor-bound.
        guard var simulation = try? GamePersistence().load() else {
            replyHandler([:])
            return
        }
        simulation.advance(to: Date())

        if let encoded = try? encoder.encode(simulation.watchSummary()) {
            replyHandler(["summary": encoded])
        } else {
            replyHandler([:])
        }

        // A watch that had to ask is a watch whose copy is old. Send the file
        // regardless of the throttle.
        sendSaveFile(simulation, force: true)
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if let error {
            logger.error("save transfer failed: \(error.localizedDescription)")
            // Let the next one through rather than waiting out the throttle.
            lastFileSent = nil
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate so a newly paired watch is picked up.
        WCSession.default.activate()
    }

    /// A freshly paired watch has nothing. Give it everything.
    func sessionWatchStateDidChange(_ session: WCSession) {
        guard session.isPaired, session.isWatchAppInstalled else { return }
        guard var simulation = try? GamePersistence().load() else { return }
        simulation.advance(to: Date())
        send(simulation, summary: simulation.watchSummary(), force: true)
    }
    #endif
}
