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

/// `@unchecked Sendable` because it genuinely is used from several places at
/// once, and the state that made that unsafe is now behind a lock.
///
/// It is handed to the background task, which runs off the main actor; it is
/// called from the app's `onChange`, which is on it; and WatchConnectivity
/// delivers its own callbacks on a queue of its own choosing. The throttle
/// counters were plain `var`s across all three — a data race the compiler
/// cannot see through an Objective-C delegate, and one it would not have
/// flagged. Everything mutable now lives in `Throttle`.
final class WatchLink: NSObject, WCSessionDelegate, @unchecked Sendable {

    private let logger = Logger(subsystem: "com.kylepeterson.flowerpower", category: "watch")
    private let encoder = JSONEncoder()

    private static let minimumInterval: TimeInterval = 15 * 60
    private static let minimumFileInterval: TimeInterval = 4 * 3600

    /// When each channel last carried something, and what it carried.
    ///
    /// A lock rather than an actor: every caller here is synchronous — a
    /// `WCSessionDelegate` callback cannot await — and the critical sections
    /// are three field comparisons.
    private final class Throttle: @unchecked Sendable {

        private let lock = NSLock()

        /// Throttles summaries: the colony ticks hourly in simulated time, but
        /// the complication budget is small and there is no point spending it
        /// on a change of two bees.
        private var lastSent: Date?
        private var lastSentSummary: WatchSummary?

        /// Throttles the save file, which is orders of magnitude bigger than a
        /// summary and only needs to be fresh enough for the watch to catch up
        /// from when it is out of touch.
        private var lastFileSent: Date?

        /// Whether something a glance would notice has changed, or enough time
        /// has passed to be worth refreshing anyway. Records the send in the
        /// same breath, so two threads cannot both decide to.
        func claimSummary(
            _ summary: WatchSummary,
            force: Bool,
            minimumInterval: TimeInterval,
            now: Date = Date()
        ) -> Bool {
            lock.lock()
            defer { lock.unlock() }

            let worthSending: Bool
            if force {
                worthSending = true
            } else if let lastSentSummary, let lastSent {
                worthSending = summary.status != lastSentSummary.status
                    || summary.topAlert?.kind != lastSentSummary.topAlert?.kind
                    || summary.season != lastSentSummary.season
                    || summary.shortHeadline != lastSentSummary.shortHeadline
                    || now.timeIntervalSince(lastSent) >= minimumInterval
            } else {
                worthSending = true
            }

            guard worthSending else { return false }
            lastSent = now
            lastSentSummary = summary
            return true
        }

        func claimFile(force: Bool, minimumInterval: TimeInterval, now: Date = Date()) -> Bool {
            lock.lock()
            defer { lock.unlock() }

            if !force, let lastFileSent,
               now.timeIntervalSince(lastFileSent) < minimumInterval {
                return false
            }
            lastFileSent = now
            return true
        }

        /// Lets the next one through rather than waiting out the throttle.
        func forgetLastFile() {
            lock.lock()
            defer { lock.unlock() }
            lastFileSent = nil
        }

        /// The same, for a summary that was claimed and then never sent.
        func forgetLastSummary() {
            lock.lock()
            defer { lock.unlock() }
            lastSent = nil
            lastSentSummary = nil
        }
    }

    private let throttle = Throttle()

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
        guard throttle.claimSummary(
            summary, force: force, minimumInterval: Self.minimumInterval
        ) else { return }

        do {
            let payload = ["summary": try encoder.encode(summary)]

            // Urgent news jumps the queue; routine updates ride the
            // complication transfer, which survives the app not running.
            if summary.status == .critical || summary.topAlert?.severity == .critical {
                if session.isReachable {
                    session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                        self?.logger.error("watch message failed: \(error.localizedDescription)")
                    }
                    return
                }
            }

            session.transferCurrentComplicationUserInfo(payload)

        } catch {
            // The claim was taken before the encode, so give it back. Without
            // this a summary that failed to encode would count as sent, and
            // the next real change would be throttled out behind it.
            throttle.forgetLastSummary()
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

        guard throttle.claimFile(
            force: force, minimumInterval: Self.minimumFileInterval
        ) else { return }

        do {
            let data = try GamePersistence.encodeForTransfer(simulation)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("colony-transfer.json")
            try data.write(to: url, options: .atomic)

            session.transferFile(url, metadata: ["kind": "save"])

        } catch {
            // The claim is already taken; give it back, so the next change is
            // not throttled out on the strength of a transfer that never went.
            throttle.forgetLastFile()
            logger.error("could not send save to watch: \(error.localizedDescription)")
        }
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
            throttle.forgetLastFile()
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
