//
//  SimulationSystem.swift
//  FlowerPowerCore
//
//  The tick is a pipeline of small, independent systems. Each one owns a single
//  aspect of colony life and communicates only through `World` and emitted
//  events. Adding a new behaviour means adding a system to the pipeline, not
//  editing a thousand-line update method.
//

import Foundation

/// Everything a system needs that is not world state: the clock, the balance
/// numbers, the random stream, the id source, and somewhere to report.
///
/// Systems are value types operating on `inout` state, so a system cannot
/// secretly retain a reference to the world between ticks. That is deliberate —
/// hidden per-system state would not be captured by save files and would break
/// offline catch-up.
public struct TickContext {

    public let clock: SimClock
    public let config: SimulationConfig

    public var rng: SeededRandom
    public var ids: IDGenerator

    public private(set) var events: [SimEvent] = []

    public init(clock: SimClock, config: SimulationConfig, rng: SeededRandom, ids: IDGenerator) {
        self.clock = clock
        self.config = config
        self.rng = rng
        self.ids = ids
    }

    public var season: Season { Season(day: clock.day) }
    public var day: Int { clock.day }
    public var hourOfDay: Int { clock.hourOfDay }
    public var isDaylight: Bool { clock.isDaylight }

    /// Systems that operate once per simulated day gate on this rather than
    /// keeping their own counters.
    public var isDayBoundary: Bool { clock.hourOfDay == 0 }

    public mutating func emit(_ event: SimEvent) {
        events.append(event)
    }

    /// Samples a value from a range using the deterministic stream.
    public mutating func sample(_ range: ClosedRange<Double>) -> Double {
        guard range.upperBound > range.lowerBound else { return range.lowerBound }
        return range.lowerBound + rng.unitValue() * (range.upperBound - range.lowerBound)
    }
}

public protocol SimulationSystem: Sendable {

    /// Identifies the system in diagnostics and profiling output.
    var name: String { get }

    /// Advances this aspect of the world by one tick.
    func update(_ world: inout World, _ context: inout TickContext)
}

extension SimulationSystem {
    public var name: String { String(describing: Self.self) }
}

/// Systems whose work is inherently daily rather than hourly. Implementing
/// `updateDaily` instead of `update` removes the boilerplate day-boundary check
/// and makes the cadence obvious at a glance.
public protocol DailySystem: SimulationSystem {
    func updateDaily(_ world: inout World, _ context: inout TickContext)
}

extension DailySystem {
    public func update(_ world: inout World, _ context: inout TickContext) {
        guard context.isDayBoundary else { return }
        updateDaily(&world, &context)
    }
}
