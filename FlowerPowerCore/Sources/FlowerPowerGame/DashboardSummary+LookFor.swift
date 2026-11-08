//
//  DashboardSummary+LookFor.swift
//  FlowerPowerGame
//
//  The one line of the overview the engine cannot write: what is out there to
//  photograph this month. It works from the real calendar and the player's
//  hemisphere, which the engine never learns, and from the catalogue's bloom
//  months, through `BloomPrompt`.
//

import Foundation
import FlowerPowerCore

extension DashboardSummary {

    /// The overview with the "look for" line in it. `hemisphere` is the
    /// player's, from settings. The watch and the widgets, which have no
    /// settings, build the engine's summary and get no such line.
    public init(
        snapshot: ColonySnapshot,
        history: ColonyHistory,
        hemisphere: Hemisphere,
        date: Date = Date()
    ) {
        var tiles = Self.tiles(for: snapshot, history: history)
        let line = Self.lookForTile(snapshot, hemisphere: hemisphere, date: date)
        // After forage, which is the other half of the same question.
        let place = tiles.firstIndex { $0.kind == .forage }.map { $0 + 1 } ?? tiles.endIndex
        tiles.insert(line, at: place)
        self.init(tiles: tiles, snapshot: snapshot)
    }

    /// The bloom prompt as a line: how many of the flowers out this month the
    /// garden still has none of, and the best of them by name.
    ///
    /// The prompt itself — the whole card, with the keystone's direction and
    /// the list — is on the Forage page the line opens. It used to sit at the
    /// foot of the overview, where it was the one thing that never fitted on
    /// the screen.
    static func lookForTile(
        _ snapshot: ColonySnapshot,
        hemisphere: Hemisphere,
        date: Date
    ) -> Tile {
        let prompt = BloomPrompt(
            date: date,
            hemisphere: hemisphere,
            patches: snapshot.patches,
            terrain: snapshot.terrain,
            wildPatches: snapshot.wildPatches
        )
        let missing = prompt.notYetPhotographed
        if let first = missing.first {
            // The best of them by name, and nothing else: "Viper's Bugloss
            // and 11 more" was cut to "Viper's Bugloss and 11 m…" in half a
            // screen's width, and the number is already the headline.
            let caption = missing.count == 1
                ? "\(first.commonName), out now"
                : "\(first.commonName) first"
            return Tile(
                kind: .lookFor,
                headline: "\(missing.count)",
                caption: caption,
                // A nudge, never a worry: there is nothing wrong with a
                // colony whose keeper has not been out this week.
                severity: .notable,
                spoken: prompt.headline
            )
        }
        return Tile(
            kind: .lookFor,
            headline: "\(prompt.inBloom.count)",
            caption: prompt.inBloom.isEmpty ? "nothing out this month" : "out now, all of them found",
            severity: .calm,
            spoken: prompt.headline
        )
    }

}
