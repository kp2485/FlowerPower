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
import WatchKit
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
            // A distinct tap for a decision arriving, a different one for
            // trouble. The watch's whole job is to be glanced at; haptics are
            // how it earns the glance.
            //
            // The decision comes first and only one tap plays, because a siege
            // usually brings an alert with it and two haptics a second apart
            // read as a malfunction rather than as two pieces of news. A
            // decision is the more urgent of the two anyway: it is the one
            // that stops being answerable.
            if let arriving = decoded.decision, arriving.kind != summary?.decision?.kind {
                WKInterfaceDevice.current().play(.notification)
            } else if decoded.topAlert?.kind != summary?.topAlert?.kind {
                if decoded.topAlert?.severity == .critical {
                    WKInterfaceDevice.current().play(.failure)
                } else if decoded.topAlert != nil {
                    WKInterfaceDevice.current().play(.notification)
                }
            }
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

    // MARK: - Answering

    /// Answers the decision on screen.
    ///
    /// Two things happen, in this order, for different reasons.
    ///
    /// The answer is applied to the watch's own copy of the colony first, so
    /// the page changes under the player's thumb whether or not the phone is in
    /// the room. That is not a pretence: `GameStore.apply(_:)` is the same code
    /// the phone will run, on a deterministic engine, so the watch computes
    /// exactly what the phone will compute and is overwritten by it next time
    /// they speak. It also means a stale tap is refused here as well — the page
    /// does not pretend to answer a siege that is over.
    ///
    /// Then it goes to the phone, which holds the colony that counts. The phone
    /// is where photographs are taken and where the canonical save lives, and
    /// the watch's copy is only ever a copy.
    func answer(_ identifier: String) {
        guard let action = DecisionAction(identifier: identifier) else { return }
        applyLocally(action)
        send(decision: identifier)
    }

    private func applyLocally(_ action: DecisionAction) {
        do {
            guard let simulation = try persistence.load() else { return }
            // A store around the watch's own save, exactly as the phone builds
            // one around its own for a notification action. The alternative is
            // a second copy of the rules that decide whether a decision is
            // still open, which is how the two ends would come to disagree.
            let store = GameStore(simulation: simulation, persistence: persistence)
            store.catchUp()
            guard store.apply(action) else { return }

            summary = store.watchSummary()
            lastUpdated = Date()
            // Worked out here rather than sent by the phone, which is what
            // `isStale` means. `apply(_:)` clears it when the phone is next
            // heard from.
            isStale = true

        } catch {
            logger.error("could not answer locally: \(error.localizedDescription)")
        }
    }

    /// Sends the answer, or queues it if the phone is not listening.
    ///
    /// `sendMessage` needs the phone reachable and delivers immediately;
    /// `transferUserInfo` is queued by the system and delivered whenever the
    /// two next speak, which may be after the watch app has been put away.
    /// A decision is worth queueing — the window is hours, not seconds, and
    /// the phone judges staleness when it arrives.
    private func send(decision identifier: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let payload = ["decision": identifier]

        // Nothing may be handed to an unactivated session, so an answer tapped
        // in the second before activation completes is lost rather than
        // queued. It is applied locally either way, and the phone's next
        // summary will quietly correct the watch — which is the right way
        // round for a copy to be wrong.
        guard session.activationState == .activated else {
            logger.error("a decision was answered before the session was up")
            return
        }

        guard session.isReachable else {
            session.transferUserInfo(payload)
            return
        }

        session.sendMessage(payload, replyHandler: nil) { [weak self] error in
            self?.logger.error("could not send a decision: \(error.localizedDescription)")
            // Reachable and it still failed, so fall back to the queue rather
            // than losing the tap. A failed send could in principle have
            // arrived anyway, so this can deliver the same answer twice —
            // which every answer here tolerates, because the second one finds
            // the decision closed and does nothing. The exception is opening
            // the nest up, which is deliberately not checked against a
            // decision at all: a duplicate would draw a second batch of comb
            // and pay for it. The colony can afford that or it would draw
            // nothing, so losing the answer is the worse of the two risks.
            WCSession.default.transferUserInfo(payload)
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
