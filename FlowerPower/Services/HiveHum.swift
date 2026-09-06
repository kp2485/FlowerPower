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

    // Parameters the render thread reads. Plain values, updated from the
    // main actor, read from the audio thread; small drift is inaudible and
    // preferable to a lock in the render callback.
    private var targetFrequency: Double = 180
    private var targetGain: Double = 0.05
    private var frequency: Double = 180
    private var gain: Double = 0
    private var phase1: Double = 0
    private var phase2: Double = 0
    private var tremoloPhase: Double = 0

    private init() {}

    // MARK: - State

    /// Sets the note from the colony's state. Called on every snapshot.
    func update(for snapshot: ColonySnapshot) {
        switch snapshot.status {
        case .collapsed:
            targetGain = 0
        case .critical where snapshot.activeThreat != nil:
            // Alarm pheromone. The pitch rises and the volume with it.
            targetFrequency = 260
            targetGain = 0.09
        default:
            if snapshot.season == .winter {
                targetFrequency = 120
                targetGain = 0.03
            } else if snapshot.isForaging {
                targetFrequency = 190
                targetGain = 0.06
            } else {
                targetFrequency = 160
                targetGain = 0.045
            }
        }
    }

    // MARK: - Running

    func start() {
        guard !isRunning else { return }

        let format = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate

        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)

            for frame in 0..<Int(frameCount) {
                // Ease toward the target so a change of state is a swell,
                // not a click.
                self.frequency += (self.targetFrequency - self.frequency) * 0.0005
                self.gain += (self.targetGain - self.gain) * 0.0005

                // Two oscillators a few hertz apart beat against each other,
                // which is most of what makes a hum sound like many wings.
                self.phase1 += 2 * .pi * self.frequency / sampleRate
                self.phase2 += 2 * .pi * (self.frequency * 1.013) / sampleRate
                self.tremoloPhase += 2 * .pi * 5.5 / sampleRate

                let tremolo = 0.85 + 0.15 * sin(self.tremoloPhase)
                let sample = Float((sin(self.phase1) * 0.6 + sin(self.phase2) * 0.4)
                                   * self.gain * tremolo)

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
        gain = 0
    }
}
