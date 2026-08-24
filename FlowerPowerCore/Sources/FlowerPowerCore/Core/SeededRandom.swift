//
//  SeededRandom.swift
//  FlowerPowerCore
//

/// SplitMix64. Deterministic, seedable, and cheap — the simulation must
/// replay identically from the same seed and tick count, otherwise offline
/// catch-up would disagree with live play.
public struct SeededRandom: RandomNumberGenerator, Codable, Equatable, Sendable {

    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform value in 0..<1.
    public mutating func unitValue() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// True with the given probability.
    public mutating func chance(_ probability: Double) -> Bool {
        unitValue() < probability
    }
}
