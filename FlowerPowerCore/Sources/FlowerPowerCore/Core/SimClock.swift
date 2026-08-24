//
//  SimClock.swift
//  FlowerPowerCore
//
//  Maps real elapsed time onto simulated time.
//

import Foundation

/// One tick is one simulated hour. Real time is mapped onto ticks so the
/// simulation can be caught up from a cold launch instead of relying on a
/// live timer — closing the app for three days must produce the same result
/// as leaving it open for three days.
public struct SimClock: Codable, Equatable, Sendable {

    /// Simulated hours in a simulated day.
    public static let ticksPerDay = 24

    /// Real seconds that must elapse to advance one tick.
    /// Default: 5 real minutes per simulated hour, so one simulated day
    /// costs two real hours.
    public var realSecondsPerTick: Double

    /// Real-world instant that tick 0 occurred at.
    public var epoch: Date

    /// Ticks elapsed since `epoch` that the simulation has actually processed.
    public private(set) var tick: Int

    /// Ceiling on how much time a single catch-up will simulate, so returning
    /// after a six-month absence cannot lock the app up in a stepping loop.
    public var maxCatchUpDays: Int

    public init(
        epoch: Date,
        tick: Int = 0,
        realSecondsPerTick: Double = 300,
        maxCatchUpDays: Int = 30
    ) {
        self.epoch = epoch
        self.tick = tick
        self.realSecondsPerTick = realSecondsPerTick
        self.maxCatchUpDays = maxCatchUpDays
    }

    public var day: Int { tick / Self.ticksPerDay }
    public var hourOfDay: Int { tick % Self.ticksPerDay }

    /// Daylight drives foraging: bees work the flowers, they do not work at night.
    public var isDaylight: Bool { (6..<20).contains(hourOfDay) }

    /// Ticks that *should* have elapsed by `date`, clamped to `maxCatchUpDays`.
    public func pendingTicks(at date: Date) -> Int {
        let elapsed = date.timeIntervalSince(epoch)
        guard elapsed > 0, realSecondsPerTick > 0 else { return 0 }
        let target = Int(elapsed / realSecondsPerTick)
        let outstanding = max(0, target - tick)
        return min(outstanding, maxCatchUpDays * Self.ticksPerDay)
    }

    /// Advances the processed-tick counter. Called by the simulation once a
    /// tick has actually been simulated.
    public mutating func commitTick() {
        tick += 1
    }

    /// Discards unsimulated backlog beyond the catch-up ceiling so the clock
    /// does not permanently lag real time after a long absence.
    public mutating func resynchronize(to date: Date) {
        let elapsed = date.timeIntervalSince(epoch)
        guard elapsed > 0, realSecondsPerTick > 0 else { return }
        tick = max(tick, Int(elapsed / realSecondsPerTick))
    }
}
