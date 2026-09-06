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

    /// How much faster the clock runs in winter, as a multiple of the base
    /// rate. 1 is uniform.
    ///
    /// Winter is a quarter of the year with nothing to photograph and little
    /// to watch. At 2 it lasts under four real days rather than seven. The
    /// mapping from real time to ticks stays a pure function of dates, so
    /// catch-up is exactly as deterministic as before and the watch's own
    /// replay lands on the same tick — the rate is part of the save.
    public var winterSpeed: Double

    public static let defaultWinterSpeed: Double = 2

    /// Real seconds already accounted for by the ticks processed so far.
    /// Kept rather than recomputed, so a catch-up walks only the pending ticks.
    public private(set) var realSecondsAtTick: Double

    public init(
        epoch: Date,
        tick: Int = 0,
        realSecondsPerTick: Double = SimClock.defaultRealSecondsPerTick,
        maxCatchUpDays: Int = SimClock.defaultMaxCatchUpDays,
        winterSpeed: Double = SimClock.defaultWinterSpeed
    ) {
        self.epoch = epoch
        self.tick = tick
        self.realSecondsPerTick = realSecondsPerTick
        self.maxCatchUpDays = maxCatchUpDays
        self.winterSpeed = max(0.25, winterSpeed)
        self.realSecondsAtTick = 0
        for index in 0..<tick {
            realSecondsAtTick += Self.seconds(forTick: index, base: realSecondsPerTick, winterSpeed: self.winterSpeed)
        }
    }

    /// Saves from before the seasonal clock carry neither field.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        epoch = try container.decode(Date.self, forKey: .epoch)
        tick = try container.decode(Int.self, forKey: .tick)
        realSecondsPerTick = try container.decode(Double.self, forKey: .realSecondsPerTick)
        maxCatchUpDays = try container.decode(Int.self, forKey: .maxCatchUpDays)
        // An old save ran at a uniform rate. Keeping it uniform means the
        // date-to-tick mapping it was written under still holds.
        winterSpeed = try container.decodeIfPresent(Double.self, forKey: .winterSpeed) ?? 1
        if let stored = try container.decodeIfPresent(Double.self, forKey: .realSecondsAtTick) {
            realSecondsAtTick = stored
        } else {
            realSecondsAtTick = Double(tick) * realSecondsPerTick
        }
    }

    /// Real seconds a particular tick lasts.
    static func seconds(forTick tick: Int, base: Double, winterSpeed: Double) -> Double {
        Season(day: tick / ticksPerDay) == .winter ? base / winterSpeed : base
    }

    public func seconds(forTick tick: Int) -> Double {
        Self.seconds(forTick: tick, base: realSecondsPerTick, winterSpeed: winterSpeed)
    }

    public var day: Int { tick / Self.ticksPerDay }
    public var hourOfDay: Int { tick % Self.ticksPerDay }

    /// Daylight drives foraging: bees work the flowers, they do not work at night.
    public var isDaylight: Bool { (6..<20).contains(hourOfDay) }

    /// Ticks that *should* have elapsed by `date`, clamped to `maxCatchUpDays`.
    ///
    /// Walks forward from the current tick summing each tick's real length,
    /// because winter ticks are shorter than the rest. Bounded by the ceiling,
    /// so the walk is at most a few thousand additions.
    public func pendingTicks(at date: Date) -> Int {
        let elapsed = date.timeIntervalSince(epoch)
        guard elapsed > 0, realSecondsPerTick > 0 else { return 0 }

        let ceiling = maxCatchUpDays * Self.ticksPerDay
        var accounted = realSecondsAtTick
        var pending = 0

        while pending < ceiling {
            let next = accounted + seconds(forTick: tick + pending)
            guard next <= elapsed else { break }
            accounted = next
            pending += 1
        }
        return pending
    }

    /// The real instant a future tick begins, walking the seasonal rate.
    /// Tests use this rather than multiplying by a constant, because winter
    /// ticks are shorter than the rest.
    public func date(atTick target: Int) -> Date {
        guard target >= tick else { return epoch.addingTimeInterval(realSecondsAtTick) }
        var elapsed = realSecondsAtTick
        for index in tick..<target {
            elapsed += seconds(forTick: index)
        }
        return epoch.addingTimeInterval(elapsed)
    }

    /// Advances the processed-tick counter. Called by the simulation once a
    /// tick has actually been simulated.
    public mutating func commitTick() {
        realSecondsAtTick += seconds(forTick: tick)
        tick += 1
    }

    /// Discards unsimulated backlog beyond the catch-up ceiling so the clock
    /// does not permanently lag real time after a long absence.
    public mutating func resynchronize(to date: Date) {
        let elapsed = date.timeIntervalSince(epoch)
        guard elapsed > 0, realSecondsPerTick > 0 else { return }

        while realSecondsAtTick + seconds(forTick: tick) <= elapsed {
            realSecondsAtTick += seconds(forTick: tick)
            tick += 1
        }
    }
}
