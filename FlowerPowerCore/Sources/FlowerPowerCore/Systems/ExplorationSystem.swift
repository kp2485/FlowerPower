//
//  ExplorationSystem.swift
//  FlowerPowerCore
//
//  How the map grows, and the only two ways it ever does.
//
//  **Foragers, on their own.** Nobody decides this. When the colony is short,
//  bees range further, and one of them comes back having found the next parish.
//  It is not a search and it is not clever: a rumoured chunk is drawn from the
//  stream, and whether anybody notices it depends on how much is actually in
//  flower there. A parish with nothing out is passed over for weeks; a field of
//  rape in May is found almost at once. That is the sense — the only sense — in
//  which the bees can be said to choose where they look.
//
//  **A scouting party, because the player sent one.** A tenth of the force for
//  three days, and at the end of it every rumoured chunk is on the map. See
//  `Simulation.sendScouts()`.
//
//  Both cost foraging and neither can reach past `FlowerPatch.maximumForagingRange`.
//  Everything ever drawn on this map was reached by a bee, which is the premise
//  `docs/WORLD.md` section 1 is built on: there is no map of the countryside and
//  no choosing where to put a hive on it — there is the hive, and the country
//  appears around it in the order the bees find it.
//
//  Runs after `ForagingSystem` in the pipeline and at the day boundary, which
//  is before any of the day's daylight ticks. So the share it commits is a
//  share the day's foraging never sees.
//

import Foundation

public struct ExplorationSystem: DailySystem {

    public init() {}

    public func updateDaily(_ world: inout World, _ context: inout TickContext) {
        // A new day: whoever wandered yesterday is back at work.
        world.exploringToday = false

        guard world.terrain != nil else { return }

        returnScouts(&world, &context)
        wander(&world, &context)
    }

    // MARK: - The party the player sent

    /// Brings a scouting party home, with the ring of rumoured ground on it.
    ///
    /// Everything rumoured, rather than a sample of it: that is what
    /// distinguishes the decision from what the foragers do anyway, and it is
    /// what the player is paying a tenth of the force for three days for. The
    /// ring is read at the moment they get back rather than when they left,
    /// because the foragers may have found something in the meantime and a
    /// party that walked past newly rumoured ground without seeing it would be
    /// an odd thing to model.
    private func returnScouts(_ world: inout World, _ context: inout TickContext) {
        guard let party = world.scoutingParty else { return }
        guard context.day >= party.returnsOnDay else { return }

        world.scoutingParty = nil

        guard let terrain = world.terrain else { return }
        let date = context.clock.date(atTick: context.clock.tick)

        // Read the ring once, before discovering anything: discovering a chunk
        // rumours the ground beyond it, and a party that kept walking outward
        // into ground it had just revealed would never come home.
        for chunk in terrain.rumoured {
            world.discover(
                chunk, ids: &context.ids, config: context.config,
                on: context.day, at: date
            )
        }
    }

    // MARK: - What the foragers do anyway

    /// A small share of the force ranges further, because there is nothing to
    /// work close in.
    ///
    /// **The cue is a dearth**, which is `World.isInDearth` — the engine's own
    /// measured notion of "short", the same one that stops brood rearing and
    /// starts robbing. The alternative was a threshold on the best candidate's
    /// `forageQuality`, and it was rejected for being a second opinion about
    /// the same thing: it would need a constant of its own, that constant
    /// would have to be kept in step with `dearthThresholdPerBee`, and the two
    /// would drift. A colony that is robbing its neighbours is a colony whose
    /// foragers are already out beyond the garden.
    private func wander(_ world: inout World, _ context: inout TickContext) {
        guard world.scoutingParty == nil else { return }
        guard world.isInDearth(context.config) else { return }
        guard world.weather.isFlyingWeather else { return }
        guard world.hive.count(performing: .foragingBee) > 0 else { return }

        guard let terrain = world.terrain else { return }
        let rumoured = terrain.rumoured
        guard !rumoured.isEmpty else { return }

        // They went. Whether they found anything is the next question, and the
        // day's foraging is short either way — which is the cost, and it is
        // paid by a colony that is already hungry, which is the point.
        world.exploringToday = true

        // One chunk, drawn from the seeded stream over the fixed rumour order.
        // Drawn before the richness test rather than picking the best, because
        // a bee blundering into the next parish is not choosing.
        let index = Int(context.rng.next() % UInt64(rumoured.count))
        let chunk = rumoured[index]

        let richness = terrain.generator.wildRichness(
            in: chunk, during: context.season, density: context.config.wildPatchDensity
        )
        guard richness > 0 else { return }

        // Proportional to what is standing there, capped well below certainty:
        // even a parish in full flow is a week or two of dearth away rather
        // than a single day's discovery.
        let chance = min(0.5, richness * context.config.explorationChance)
        guard context.rng.chance(chance) else { return }

        world.discover(
            chunk, ids: &context.ids, config: context.config,
            on: context.day,
            at: context.clock.date(atTick: context.clock.tick)
        )
    }
}
