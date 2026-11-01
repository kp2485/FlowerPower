//
//  LenientConfig.swift
//  FlowerPowerCore
//
//  A save written before a constant existed must still open.
//
//  `SimulationConfig` is saved with every colony and decoded by the compiler's
//  own decoder, which fails outright on a missing key — default value or not.
//  So the first update that added a constant (the country added nine) made
//  every save on every phone undecodable, and the app, finding a save it could
//  not read, started a fresh colony over it. The config is now read leniently:
//  if it will not decode as stored, what was stored is laid over the standard
//  preset key by key, so a new constant takes its standard value and every
//  constant the player's colony already had keeps the one it had.
//

import Foundation

/// Any JSON value, so a stored config can be read without knowing its shape.
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension SimulationConfig {

    /// A stored config laid over the standard one, for a config written by an
    /// older build. Keys the standard config no longer has are dropped; a
    /// stored value that will not decode in its new shape gives way to the
    /// standard one.
    static func lenient(_ stored: JSONValue) -> SimulationConfig {
        guard
            let data = try? JSONEncoder().encode(SimulationConfig.standard),
            case .object(var merged)? = try? JSONDecoder().decode(JSONValue.self, from: data),
            case .object(let overrides) = stored
        else { return .standard }

        for (key, value) in overrides where merged[key] != nil {
            var trial = merged
            trial[key] = value
            if let encoded = try? JSONEncoder().encode(JSONValue.object(trial)),
               (try? JSONDecoder().decode(SimulationConfig.self, from: encoded)) != nil {
                merged = trial
            }
        }

        guard
            let encoded = try? JSONEncoder().encode(JSONValue.object(merged)),
            var config = try? JSONDecoder().decode(SimulationConfig.self, from: encoded)
        else { return .standard }

        // Two exceptions to a new constant taking its standard value, both for
        // a colony saved before it existed. The ceiling is half of what makes
        // Forgiving survive a second year, and Forgiving would otherwise stay
        // on the settings that were killing it. Nurse reversion is off on
        // Harsh, and the standard value would quietly make Harsh easier.
        func isLike(_ preset: SimulationConfig) -> Bool {
            abs(config.pathogenArrivalMultiplier - preset.pathogenArrivalMultiplier) < 0.001
                && abs(config.predatorStrength - preset.predatorStrength) < 0.001
        }
        if overrides["storesCeilingCells"] == nil, isLike(.gentle) {
            config.storesCeilingCells = SimulationConfig.gentle.storesCeilingCells
        }
        if overrides["nurseReversionShare"] == nil, isLike(.harsh) {
            config.nurseReversionShare = SimulationConfig.harsh.nurseReversionShare
        }
        return config
    }
}
