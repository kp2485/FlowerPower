//
//  EnvironmentSystems.swift
//  FlowerPowerCore
//

import Foundation

/// Rolls the daily weather. Runs first in the pipeline, because almost
/// everything downstream depends on whether the bees can fly today.
public struct WeatherSystem: DailySystem {

    public init() {}

    public func updateDaily(_ world: inout World, _ context: inout TickContext) {
        let previousSky = world.weather.sky

        world.weather = Weather.next(
            after: world.weather,
            season: context.season,
            rng: &context.rng
        )

        if world.weather.sky != previousSky {
            context.emit(.weatherChanged(world.weather.sky))
        }

        if !world.weather.isFlyingWeather {
            context.emit(.groundedByWeather)
        }
    }
}

/// Flowers regrow overnight while in bloom, and stop dead out of season.
///
/// Without regrowth the player would have to photograph continuously to keep a
/// colony alive, which turns a habit into a chore. With it, a well-chosen patch
/// keeps paying out — so the interesting decision becomes *which* flowers to
/// photograph, not how many.
public struct PatchSystem: DailySystem {

    public init() {}

    public func updateDaily(_ world: inout World, _ context: inout TickContext) {
        let season = context.season
        let seasonalRegrowth = season.patchRegrowthMultiplier

        for index in world.patches.indices {
            let wasInBloom = world.patches[index].isInBloom(during: season)

            guard wasInBloom, seasonalRegrowth > 0 else {
                if !wasInBloom && !world.patches[index].isDepleted {
                    context.emit(.patchOutOfBloom(world.patches[index].id))
                }
                continue
            }

            // Rain is not all bad: it is what refills the nectaries.
            let rainBonus = world.weather.sky == .rain ? 1.35 : 1.0
            let rate = context.config.patchDailyRegrowth * seasonalRegrowth * rainBonus

            world.patches[index].regrow(rate: rate)
            // Recruitment is re-decided from scratch every day by the dance.
            world.patches[index].recruitedForagers = 0
        }
    }
}

/// Perishables decay. Royal jelly is glandular and lasts days; nectar ferments
/// if it is not ripened; honey keeps essentially forever, which is the whole
/// point of making it.
public struct SpoilageSystem: DailySystem {

    public init() {}

    public func updateDaily(_ world: inout World, _ context: inout TickContext) {
        for kind in ResourceKind.allCases {
            let rate = kind.dailySpoilage
            guard rate > 0 else { continue }

            // A propolis-sealed, well-ventilated nest keeps stores better.
            let preservation = 1.0 - 0.4 * world.hive.propolisEnvelope
            world.hive.resources.drain(
                world.hive.resources[kind] * rate * preservation,
                of: kind
            )
        }
    }
}

/// Foragers collect propolis and seal the nest with it. The resulting envelope
/// is measurably antimicrobial — colonies with good propolis envelopes carry
/// lower pathogen loads and spend less on immune response.
public struct PropolisSystem: DailySystem {

    public init() {}

    public func updateDaily(_ world: inout World, _ context: inout TickContext) {
        let target = context.config.targetPropolisEnvelope

        if world.hive.propolisEnvelope < target, world.hive.resources[.propolis] > 1 {
            let applied = world.hive.resources.drain(2.0, of: .propolis)
            world.hive.propolisEnvelope = min(
                target,
                world.hive.propolisEnvelope + applied * context.config.propolisPerUnit
            )
        }

        // The envelope degrades and needs maintaining.
        world.hive.propolisEnvelope = max(
            0,
            world.hive.propolisEnvelope - context.config.propolisDecayPerDay
        )
    }
}
