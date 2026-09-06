//
//  PostureSystem.swift
//  FlowerPowerCore
//
//  Postures expire, the entrance is unsealed in spring, and the colony's own
//  instinct seals it in autumn if nobody said otherwise.
//

import Foundation

public struct PostureSystem: DailySystem {

    public init() {}

    public func updateDaily(_ world: inout World, _ context: inout TickContext) {
        expirePosture(&world, &context)
        manageEntrance(&world, &context)
    }

    private func expirePosture(_ world: inout World, _ context: inout TickContext) {
        guard world.posture != .instinct else { return }
        guard let until = world.postureUntilDay, context.day >= until else { return }

        world.posture = .instinct
        world.postureUntilDay = nil
        context.emit(.postureAdopted(.instinct))
    }

    /// The autumn decision, made by instinct unless the player made it first.
    ///
    /// A colony with propolis to spare narrows its entrance as the weather
    /// turns. That keeps mice out and warmth in, and it costs ventilation —
    /// damp is its own slow damage in a clustered nest. The player may
    /// countermand it in autumn; once winter has set in, the bees have
    /// clustered and nobody is doing any building.
    ///
    /// In spring the bees chew it open again, and the choice resets.
    private func manageEntrance(_ world: inout World, _ context: inout TickContext) {
        switch context.season {
        case .autumn:
            // Instinct decides if the player has not; `entranceDecision` is
            // the player's word, and nil means none was given. It waits until
            // late in the season, once the ivy is nearly over. Sealing in
            // the middle of autumn cost a measurable share of the last flow,
            // and every colony paid it because instinct decided.
            guard world.entranceDecision == nil,
                  Season.progress(context.day) >= 0.75,
                  !world.entranceSealed else { return }

            if world.hive.resources[.propolis] >= context.config.entranceSealPropolis {
                world.hive.resources.drain(context.config.entranceSealPropolis, of: .propolis)
                world.entranceSealed = true
                context.emit(.entranceSealed(true))
            }

        case .spring:
            if world.entranceSealed, Season.progress(context.day) >= 0.1 {
                world.entranceSealed = false
                context.emit(.entranceSealed(false))
            }
            world.entranceDecision = nil

        case .summer, .winter:
            break
        }
    }
}
