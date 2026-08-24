//
//  Weather.swift
//  FlowerPowerCore
//
//  Weather is the single biggest determinant of whether a colony thrives.
//  A week of rain in the main flow can starve a hive that was doing fine.
//

import Foundation

public enum Sky: String, Codable, CaseIterable, Sendable {
    case clear
    case cloudy
    case rain
    case storm

    /// Fraction of normal foraging achieved. Bees will not fly in rain, and a
    /// storm keeps them home entirely.
    public var forageFactor: Double {
        switch self {
        case .clear: return 1.0
        case .cloudy: return 0.65
        case .rain: return 0.1
        case .storm: return 0.0
        }
    }

    public var displayName: String {
        switch self {
        case .clear: return "Clear"
        case .cloudy: return "Cloudy"
        case .rain: return "Rain"
        case .storm: return "Storm"
        }
    }
}

public struct Weather: Codable, Equatable, Sendable {

    public var sky: Sky
    /// Outside air temperature in Celsius.
    public var temperatureCelsius: Double
    /// 0...1. High humidity slows the ripening of nectar into honey.
    public var humidity: Double
    /// Metres per second. Strong wind grounds foragers even under a clear sky.
    public var windSpeed: Double

    public init(
        sky: Sky = .clear,
        temperatureCelsius: Double = 18,
        humidity: Double = 0.5,
        windSpeed: Double = 2
    ) {
        self.sky = sky
        self.temperatureCelsius = temperatureCelsius
        self.humidity = humidity
        self.windSpeed = windSpeed
    }

    /// Honey bees essentially do not fly below about 12C, and are grounded by
    /// wind above roughly 10 m/s.
    public static let minimumFlightTemperature: Double = 10
    public static let maximumFlightWind: Double = 10

    public var isFlyingWeather: Bool {
        sky != .storm
            && temperatureCelsius >= Self.minimumFlightTemperature
            && windSpeed < Self.maximumFlightWind
    }

    /// Combined multiplier on foraging output, 0 when the bees stay home.
    public var forageFactor: Double {
        guard isFlyingWeather else { return 0 }

        // Foraging ramps up between the flight minimum and about 20C.
        let warmth = min(1.0, max(0.0, (temperatureCelsius - Self.minimumFlightTemperature) / 10.0))
        let calm = 1.0 - min(1.0, windSpeed / Self.maximumFlightWind) * 0.5

        return sky.forageFactor * (0.4 + 0.6 * warmth) * calm
    }

    /// Nectar is ripened by evaporation, which stalls in damp air.
    public var ripeningFactor: Double {
        1.0 - 0.6 * min(1.0, max(0.0, humidity))
    }

    /// Rolls the next day's weather, anchored to the season and nudged toward
    /// persistence so runs of good and bad weather emerge rather than the sky
    /// flickering randomly every day.
    public static func next(
        after previous: Weather,
        season: Season,
        rng: inout SeededRandom
    ) -> Weather {
        let normals = season.weatherNormals

        // 60% chance the sky simply persists, which is roughly how real weather
        // behaves and makes a wash-out week feel like an event.
        let sky: Sky
        if rng.chance(0.6) {
            sky = previous.sky
        } else {
            sky = normals.skyDistribution.sample(&rng)
        }

        // Temperature performs a bounded random walk around the seasonal mean.
        let drift = (normals.meanTemperature - previous.temperatureCelsius) * 0.4
        let noise = (rng.unitValue() - 0.5) * normals.temperatureSwing
        var temperature = previous.temperatureCelsius + drift + noise
        // Overcast and wet days run cooler.
        temperature -= (sky == .rain || sky == .storm) ? 3 : 0
        temperature = min(max(temperature, normals.meanTemperature - 18), normals.meanTemperature + 14)

        let humidity: Double
        switch sky {
        case .clear: humidity = 0.3 + rng.unitValue() * 0.25
        case .cloudy: humidity = 0.45 + rng.unitValue() * 0.25
        case .rain, .storm: humidity = 0.75 + rng.unitValue() * 0.25
        }

        let wind: Double
        switch sky {
        case .storm: wind = 9 + rng.unitValue() * 8
        case .rain: wind = 4 + rng.unitValue() * 5
        case .cloudy: wind = 2 + rng.unitValue() * 5
        case .clear: wind = rng.unitValue() * 4
        }

        return Weather(
            sky: sky,
            temperatureCelsius: temperature,
            humidity: humidity,
            windSpeed: wind
        )
    }
}

/// Seasonal weather characteristics.
public struct WeatherNormals: Sendable {
    public let meanTemperature: Double
    public let temperatureSwing: Double
    public let skyDistribution: WeightedChoice<Sky>
}

/// Small weighted sampler, so probability tables read declaratively at the call
/// site instead of as chains of `if rng.chance(...)`.
public struct WeightedChoice<Value: Sendable>: Sendable {

    private let entries: [(value: Value, weight: Double)]
    private let totalWeight: Double

    public init(_ entries: [(Value, Double)]) {
        self.entries = entries.map { (value: $0.0, weight: max(0, $0.1)) }
        self.totalWeight = self.entries.reduce(0) { $0 + $1.weight }
    }

    public func sample(_ rng: inout SeededRandom) -> Value {
        precondition(!entries.isEmpty, "WeightedChoice requires at least one entry")
        guard totalWeight > 0 else { return entries[0].value }

        var roll = rng.unitValue() * totalWeight
        for entry in entries {
            roll -= entry.weight
            if roll <= 0 { return entry.value }
        }
        return entries[entries.count - 1].value
    }
}
