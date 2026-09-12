//
//  Symbols.swift
//  FlowerPowerCore
//
//  The SF Symbol for each thing the engine models.
//
//  These were nine exhaustive `switch` statements in `Theme`, and most of them
//  were a second and third time over in `WatchTheme` and `WidgetTheme` — three
//  files, in three targets, none of which anything on the development machine
//  can compile. `ColonyStatus.symbolName` was already here, with a comment
//  saying why: "so both apps show the same icon for the same state". This is
//  the rest of it.
//
//  It matters more than tidiness. `SimEvent.narration` was a switch in a view
//  too, and it had been a build failure for however long it took nobody to
//  open Xcode, because the engine gained seven cases and the view did not.
//  Anything that switches over an engine type belongs here, where the compiler
//  checks it is exhaustive on every platform the package builds on and
//  `SymbolTests` checks that each case actually says something.
//
//  Colours stay in the app. `Color` is SwiftUI and the package does not import
//  it — and a colour is a house style in a way that "a shield means defence"
//  is not.
//

import Foundation

// MARK: - The year

public extension Season {

    var symbolName: String {
        switch self {
        case .spring: return "leaf.fill"
        case .summer: return "sun.max.fill"
        case .autumn: return "wind"
        case .winter: return "snowflake"
        }
    }
}

public extension Sky {

    var symbolName: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .cloudy: return "cloud.fill"
        case .rain: return "cloud.rain.fill"
        case .storm: return "cloud.bolt.rain.fill"
        }
    }
}

// MARK: - The colony

public extension ResourceKind {

    var symbolName: String {
        switch self {
        case .honey: return "drop.fill"
        case .nectar: return "drop"
        case .pollen: return "circle.grid.3x3.fill"
        case .beeBread: return "square.grid.3x3.fill"
        case .royalJelly: return "sparkles"
        case .wax: return "hexagon.fill"
        case .propolis: return "shield.lefthalf.filled"
        case .water: return "drop.triangle.fill"
        }
    }
}

public extension WorkerJob {

    var symbolName: String {
        switch self {
        case .cellCleaner: return "sparkles"
        case .nurseBee: return "heart.fill"
        case .mortuary: return "arrow.up.bin.fill"
        case .droneFeeder: return "fork.knife"
        case .queenAttendant: return "crown.fill"
        case .nectarConcentrator: return "drop.degreesign"
        case .pollenPacker: return "shippingbox.fill"
        case .honeycombBuilder: return "hammer.fill"
        case .fanning: return "wind"
        case .waterCarrier: return "drop.triangle"
        case .guardBee: return "shield.fill"
        case .foragingBee: return "figure.walk.motion"
        }
    }
}

public extension BeeKind {

    var symbolName: String {
        switch self {
        case .queen: return "crown.fill"
        case .worker: return "figure.walk.motion"
        case .drone: return "circle.fill"
        }
    }
}

public extension DevelopmentStage {

    var symbolName: String {
        switch self {
        case .egg: return "circle.dotted"
        case .larva: return "circle.dashed"
        case .pupa: return "circle.fill"
        case .adult: return "hexagon.fill"
        }
    }
}

public extension HiveLocationType {

    var symbolName: String {
        switch self {
        case .livingTreeCavity: return "tree.fill"
        case .fallenTree: return "tree"
        case .underTreeBranch: return "cloud.sun.fill"
        case .cliff: return "mountain.2.fill"
        case .cave: return "mountain.2"
        case .insideWalls: return "building.2.fill"
        case .humanStructure: return "house.lodge.fill"
        case .termiteMound: return "triangle.fill"
        case .animalBurrow: return "circle.bottomhalf.filled"
        case .nestbox: return "shippingbox.fill"
        }
    }
}

// MARK: - What comes to the nest

public extension AttackStyle {

    var symbolName: String {
        switch self {
        case .catastrophic: return "exclamationmark.octagon.fill"
        case .entrance: return "door.left.hand.closed"
        case .field: return "eye.trianglebadge.exclamationmark"
        case .comb: return "ant.fill"
        case .pilfer: return "hand.raised.fill"
        case .parasite: return "microbe.fill"
        }
    }
}

public extension Predator {

    /// A predator is drawn by how it attacks, not by what it is. Twenty-three
    /// species share six ways in.
    var symbolName: String { attackStyle.symbolName }
}

public extension Pathogen {

    var symbolName: String { "microbe.fill" }
}

// MARK: - The record

public extension AlmanacEntry.Kind {

    var symbolName: String {
        switch self {
        case .season: return "calendar"
        case .forage: return "leaf.fill"
        case .queen: return "crown.fill"
        case .swarm: return "arrow.triangle.branch"
        case .threat: return "exclamationmark.shield.fill"
        case .disease: return "microbe.fill"
        case .stores: return "drop.fill"
        case .harvest: return "hand.raised.fill"
        case .colony: return "hexagon.fill"
        }
    }
}

public extension Milestone {

    /// A badge needs a face of its own, so these are deliberately not shared
    /// with the symbols above: the point of a grid of two dozen badges is that
    /// the player can tell them apart at a glance.
    var symbolName: String {
        switch self {
        case .firstFlower: return "camera.fill"
        case .tenFlowers: return "photo.on.rectangle.angled"
        case .placedToFamily: return "text.magnifyingglass"
        case .fiveFamilies: return "leaf.fill"
        case .tenFamilies: return "tree.fill"
        case .gardenAllYear: return "calendar"
        case .firstSharedFlower: return "gift.fill"

        case .firstComb: return "hexagon.fill"
        case .firstBrood: return "circle.hexagongrid.fill"
        case .hundredAdults: return "figure.walk.motion"
        case .twoHundredAdults: return "person.3.fill"
        case .fiveHundredAdults: return "chart.line.uptrend.xyaxis"

        case .firstQueenMated: return "crown.fill"
        case .supersedureSurvived: return "arrow.triangle.2.circlepath"
        case .queenNamed: return "signature"

        case .firstSwarm: return "arrow.triangle.branch"
        case .swarmTalkedOut: return "hand.raised.fill"
        case .firstSplit: return "scissors"

        case .firstHoney: return "drop.fill"
        case .sealedForWinter: return "shield.lefthalf.filled"
        case .firstWinterSurvived: return "snowflake"
        case .secondWinterSurvived: return "snowflake.circle.fill"

        case .firstRaidRepelled: return "shield.fill"
        case .tenRaidsRepelled: return "checkmark.shield.fill"
        }
    }
}

public extension QueenCell.Purpose {

    var symbolName: String {
        switch self {
        case .swarm: return "arrow.triangle.branch"
        case .supersedure: return "crown.fill"
        case .emergency: return "exclamationmark.triangle.fill"
        }
    }
}

public extension SimEvent.Severity {

    var symbolName: String {
        switch self {
        case .critical: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .notable: return "info.circle.fill"
        case .routine: return "circle.fill"
        }
    }
}
