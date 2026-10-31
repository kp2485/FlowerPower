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

    private let logger = Logger(subsystem: "com.linwoodtechnologies.flowerpower", category: "watch")
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

        enum SummaryClaim {
            /// Nothing a glance would notice.
            case none
            /// Fresher numbers, a new headline, a new season: worth having,
            /// not worth spending the complication budget on.
            case routine
            /// A decision opened or closed, the status or the top alert moved.
            case important
        }

        /// Whether something a glance would notice has changed, or enough time
        /// has passed to be worth refreshing anyway, and how much it matters.
        /// Records the send in the same breath, so two threads cannot both
        /// decide to.
        func claimSummary(
            _ summary: WatchSummary,
            force: Bool,
            minimumInterval: TimeInterval,
            now: Date = Date()
        ) -> SummaryClaim {
            lock.lock()
            defer { lock.unlock() }

            let claim: SummaryClaim
            if force {
                claim = .important
            } else if let lastSentSummary, let lastSent {
                if summary.status != lastSentSummary.status
                    || summary.topAlert?.kind != lastSentSummary.topAlert?.kind
                    // A decision opening or closing is the one thing the watch
                    // exists for, and none of the others necessarily moves
                    // when one does — a siege beginning need not change the
                    // status, the top alert or the headline. Without this a
                    // question with half a day to answer it could wait out
                    // the fifteen-minute throttle first.
                    || summary.decision?.kind != lastSentSummary.decision?.kind {
                    claim = .important
                } else if summary.season != lastSentSummary.season
                    || summary.shortHeadline != lastSentSummary.shortHeadline
                    || now.timeIntervalSince(lastSent) >= minimumInterval {
                    claim = .routine
                } else {
                    claim = .none
                }
            } else {
                claim = .important
            }

            guard claim != .none else { return .none }
            lastSent = now
            lastSentSummary = summary
            return claim
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

        /// Transfers cancelled because a newer save replaced them. They report
        /// back as failures, and a failure lets the next file straight
        /// through — so without remembering these, a watch out of range was
        /// sent a fresh save, cancelling the last, on every change.
        private var cancelled: Set<URL> = []

        func markCancelled(_ url: URL) {
            lock.lock()
            defer { lock.unlock() }
            cancelled.insert(url)
        }

        func wasCancelled(_ url: URL) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled.remove(url) != nil
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

    /// The running interface, when there is one.
    ///
    /// An answer tapped on the watch has to go through the store the player is
    /// looking at, if there is one. Writing it to the save file instead — which
    /// is what the notification path does, and what this did before it could
    /// receive anything — would work right up until the store's next catch-up
    /// overwrote the file from its own copy of the colony, taking the decision
    /// with it. `FlowerPowerApp` hands it over when the interface appears;
    /// `NotificationActions.handle` is the fallback when there is none, which
    /// is the case this is woken in the background.
    ///
    /// Weak, and main-actor-isolated rather than behind the lock, because
    /// `GameStore` is `@MainActor` and there is nothing to be gained by
    /// reaching it from anywhere else.
    @MainActor weak var store: GameStore?

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
        // Paired and installed, as `sendSaveFile` already asked. Without it a
        // phone with no watch queued a transfer on every catch-up, and each
        // one failed into the console as "WCSession is not paired".
        guard session.activationState == .activated, session.isPaired,
              session.isWatchAppInstalled else { return }
        let claim = throttle.claimSummary(
            summary, force: force, minimumInterval: Self.minimumInterval
        )
        guard claim != .none else { return }

        do {
            let payload = ["summary": try encoder.encode(summary)]

            // Urgent news jumps the queue, and falls back to the queue if the
            // message does not get through — it used to be logged and lost,
            // and a critical change then waited out the throttle.
            if summary.status == .critical || summary.topAlert?.severity == .critical,
               session.isReachable {
                session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                    self?.logger.error("watch message failed: \(error.localizedDescription)")
                    WCSession.default.transferCurrentComplicationUserInfo(payload)
                }
                return
            }

            // The complication transfer has a budget of about fifty a day, and
            // the headline alone changes every simulated day — two real hours.
            // Spent on routine updates it ran out, after which every transfer
            // became ordinary queued user info and arrived in a stale burst.
            // So the budget is kept for what matters, and everything else goes
            // as the application context, where only the latest is kept.
            if claim == .important, session.isComplicationEnabled,
               session.remainingComplicationUserInfoTransfers > 0 {
                session.transferCurrentComplicationUserInfo(payload)
            } else {
                try session.updateApplicationContext(payload)
            }

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
            // A file of its own each time. They all used to share one path,
            // rewritten while earlier transfers of it could still be queued.
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("colony-transfer-\(UUID().uuidString).json")
            try data.write(to: url, options: .atomic)

            // Only the newest save is worth delivering. A watch out of range
            // collected a backlog, and an older save landing after a newer one
            // undid whatever the newer one carried.
            for transfer in session.outstandingFileTransfers
            where transfer.file.metadata?["kind"] as? String == "save" {
                let stale = transfer.file.fileURL
                throttle.markCancelled(stale)
                transfer.cancel()
                try? FileManager.default.removeItem(at: stale)
            }

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

    /// An answer tapped on the watch.
    ///
    /// Sent without a reply handler, which is why this is a second
    /// `didReceiveMessage` beside the one above: WatchConnectivity calls the
    /// replying variant only when the sender asked for a reply. There is
    /// nothing to reply with — the watch has already applied the answer to its
    /// own copy for the player to see, and is not waiting on the phone to
    /// agree.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    /// The same, queued: a tap made with the phone out of range arrives here
    /// whenever the two next speak, which may be hours later. Nothing about
    /// handling it is different, because staleness was never assumed away —
    /// `GameStore.apply(_:)` judges the answer against the colony as it is now.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        receive(userInfo)
    }

    private func receive(_ payload: [String: Any]) {
        guard let identifier = payload["decision"] as? String,
              let action = DecisionAction(identifier: identifier) else { return }

        // Delivered on a queue of WatchConnectivity's choosing, and everything
        // below is main-actor work.
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let store = self.store {
                // A watch message can wake a suspended app whose store is
                // hours behind. Without catching up first the answer is judged
                // against a colony that has not got to the decision yet, and
                // the save afterwards writes that old colony over whatever a
                // widget, notification or background refresh put there since.
                store.catchUp()
                if !store.apply(action) {
                    self.logger.debug(
                        "a decision from the watch arrived too late: \(identifier, privacy: .public)"
                    )
                }
                return
            }
            // No interface: the save file, by the same path a notification
            // action takes.
            _ = NotificationActions.handle(actionIdentifier: identifier)
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let url = fileTransfer.file.fileURL
        try? FileManager.default.removeItem(at: url)
        if throttle.wasCancelled(url) { return }
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
