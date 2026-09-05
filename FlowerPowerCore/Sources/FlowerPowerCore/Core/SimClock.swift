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
    ///
    /// 5 real minutes per simulated hour, so a simulated day costs two real
    /// hours and a simulated year about thirty real days. This is a deliberate
    /// choice rather than a leftover, and it is a compromise between two
    /// things that pull opposite ways:
    ///
    /// - A player who opens the app once a day should find the colony visibly
    ///   changed. At this rate twelve simulated days pass between daily
    ///   visits, which is most of a build-up or most of a dearth.
    /// - Winter is a quarter of the year and there is nothing to photograph in
    ///   it, so it is the one stretch that can bore. At this rate it lasts
    ///   about a week of real time, which is survivable. Slowing the clock to
    ///   make the good seasons last also makes winter drag, so the answer to a
    ///   dull winter is to give the player something to do in it, not to
    ///   change this number.
    public var realSecondsPerTick: Double

    /// The shipped rate, named so the reasoning above has somewhere to live
    /// and so tests can talk about real time without restating it.
    public static let defaultRealSecondsPerTick: Double = 300

    /// Real-world instant that tick 0 occurred at.
    public var epoch: Date

    /// Ticks elapsed since `epoch` that the simulation has actually processed.
    public private(set) var tick: Int

    /// Ceiling on how much time a single catch-up will simulate, so returning
    /// after a six-month absence cannot lock the app up in a stepping loop.
    ///
    /// Everything past the ceiling is *skipped*: `resynchronize(to:)` jumps
    /// the clock forward and the colony never lives those days. That is a lie
    /// told to the player, so the ceiling should be as high as the engine can
    /// afford rather than as low as is comfortable.
    public var maxCatchUpDays: Int

    /// Days of backlog a single catch-up will simulate.
    ///
    /// Was 30, which is only two and a half real days of absence — a long
    /// weekend away and the colony was quietly teleported. 180 covers a
    /// fortnight away, and is affordable: catching up the full ceiling is
    /// measured in `CatchUpPerformanceTests`, which holds it to a budget the
    /// watch's widget extension can meet on much slower hardware than the
    /// machine the figure was taken on.
    public static let defaultMaxCatchUpDays = 180

    public init(
        epoch: Date,
        tick: Int = 0,
        realSecondsPerTick: Double = SimClock.defaultRealSecondsPerTick,
        maxCatchUpDays: Int = SimClock.defaultMaxCatchUpDays
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
