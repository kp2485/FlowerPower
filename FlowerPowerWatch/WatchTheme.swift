//
//  WatchTheme.swift
//  FlowerPower Watch
//
//  Kept in its own file because two targets need it: the watch app and the
//  widget extension that hosts HiveComplication. A type can only be compiled
//  into a target whose membership includes its file, and the complication
//  cannot pull in WatchRootView without also pulling in WatchColonyModel.
//

import SwiftUI
import FlowerPowerCore

/// The watch shares the phone's colours but not its file: `Theme` belongs to
/// the iOS target. This file is a member of both the watch app and the widget
/// extension.
enum WatchTheme {

    static let honey = Color(red: 0.93, green: 0.68, blue: 0.13)
    static let worker = Color(red: 0.85, green: 0.65, blue: 0.16)
    static let alarm = Color(red: 0.82, green: 0.25, blue: 0.20)
    static let caution = Color(red: 0.90, green: 0.55, blue: 0.10)
    static let healthy = Color(red: 0.30, green: 0.62, blue: 0.36)

    static func colour(for status: ColonyStatus) -> Color {
        switch status {
        // Grey rather than red. Red is an alarm, and an alarm asks the player
        // to do something; there is nothing left to do about a collapse.
        case .collapsed: return .secondary
        case .critical: return alarm
        case .struggling: return caution
        case .steady: return honey
        case .thriving: return healthy
        }
    }

    static func colour(for severity: SimEvent.Severity) -> Color {
        switch severity {
        case .critical: return alarm
        case .warning: return caution
        case .notable: return honey
        case .routine: return .secondary
        }
    }

    /// The engine owns the symbol names — see `Symbols.swift` in the package.
    /// This was the same switch as the phone's, written out a second time in a
    /// file no compiler here can see.
    static func symbol(for season: Season) -> String { season.symbolName }
}
