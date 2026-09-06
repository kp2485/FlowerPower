//
//  HiveHum.swift
//  FlowerPower
//
//  The sound of the colony, while the app is open.
//
//  A soft hum that changes with the colony's state: the steady drone of a
//  colony at work, the lower, slower note of a winter cluster, and the sharp
//  rising pitch of a colony that has been alarmed — which is a real thing a
//  beekeeper listens for. It is the cheapest way to make the colony feel
//  alive, and the easiest to overdo, so it is quiet, it is off by default,
//  and it stops the moment the app leaves the foreground.
//
//  No audio files. The hum is synthesised, because a real hive recording is
//  a large asset for a small effect and cannot be varied continuously; a
//  couple of detuned oscillators with a slow tremolo sound more like bees
//  than most recordings do through a phone speaker.
//

import Foundation
import AVFoundation
import FlowerPowerCore

@MainActor
final class HiveHum {

    static let shared = HiveHum()

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var isRunning = false

    /// Everything the render callback touches, in one box that does not belong
    /// to the main actor.
    ///
    /// It cannot: the audio render thread is real-time and calls in from
    /// nowhere, so a `@MainActor` property is unreachable from there and the
    /// compiler says so under the Swift 6 language mode. The box is
    /// deliberately lock-free — a lock in a render callback is a dropout
    /// waiting to happen — and everything in it is a `Double` written from one
    /// place and read from one place, where a torn or stale read means a
    /// fraction of a cycle of drift that nobody can hear.
    private let tone = Tone()

    private init() {}

    /// The oscillator's state, shared with the render thread.
    ///
    /// `@unchecked Sendable` on purpose, and honestly: the unchecked part is
    /// the deliberate absence of synchronisation described above, not an
    /// oversight.
    private final class Tone: @unchecked Sendable {
        // Written from the main actor, read from the audio thread.
        var targetFrequency: Double = 180
        var targetGain: Double = 0.05
        // Only ever touched by the audio thread.
        var frequency: Double = 180
        var gain: Double = 0
        var phase1: Double = 0
        var phase2: Double = 0
        var tremoloPhase: Double = 0
    }

    // MARK: - State

    /// Sets the note from the colony's state. Called on every snapshot.
    func update(for snapshot: ColonySnapshot) {
        switch snapshot.status {
        case .collapsed:
            tone.targetGain = 0
        case _ where snapshot.alarm > 0.15:
            // Alarm pheromone, read rather than guessed at. This used to fire
            // on "critical, and something is at the entrance", which is a
            // reasonable proxy for a roused colony and not the same thing: a
            // healthy colony that has just seen off a wasp is roaring, and a
            // dying one under siege may barely be able to muster a hum.
            //
            // The pitch and the volume both ride the signal, so the hive rises
            // as the raid arrives and settles over the following hours, which
            // is what a colony actually sounds like.
            tone.targetFrequency = 190 + 90 * snapshot.alarm
            tone.targetGain = 0.055 + 0.045 * snapshot.alarm
        default:
            if snapshot.season == .winter {
                tone.targetFrequency = 120
                tone.targetGain = 0.03
            } else if snapshot.isForaging {
                tone.targetFrequency = 190
                tone.targetGain = 0.06
            } else {
                tone.targetFrequency = 160
                tone.targetGain = 0.045
            }
        }
    }

    // MARK: - Running

    func start() {
        guard !isRunning else { return }

        let format = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate

        // The box rather than `self`: the render block is not main-actor
        // isolated and cannot capture something that is.
        let tone = self.tone

        let node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)

            for frame in 0..<Int(frameCount) {
                // Ease toward the target so a change of state is a swell,
                // not a click.
                tone.frequency += (tone.targetFrequency - tone.frequency) * 0.0005
                tone.gain += (tone.targetGain - tone.gain) * 0.0005

                // Two oscillators a few hertz apart beat against each other,
                // which is most of what makes a hum sound like many wings.
                tone.phase1 += 2 * .pi * tone.frequency / sampleRate
                tone.phase2 += 2 * .pi * (tone.frequency * 1.013) / sampleRate
                tone.tremoloPhase += 2 * .pi * 5.5 / sampleRate

                let tremolo = 0.85 + 0.15 * sin(tone.tremoloPhase)
                let sample = Float((sin(tone.phase1) * 0.6 + sin(tone.phase2) * 0.4)
                                   * tone.gain * tremolo)

                for buffer in buffers {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    data[frame] = sample
                }
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        source = node

        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            isRunning = true
        } catch {
            // No sound is not a problem worth surfacing.
            isRunning = false
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.stop()
        if let source { engine.detach(source) }
        source = nil
        isRunning = false
        tone.gain = 0
    }
}
