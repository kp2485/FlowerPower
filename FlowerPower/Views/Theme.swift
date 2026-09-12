//
//  Theme.swift
//  FlowerPower
//
//  One place for the game's visual vocabulary, so the phone and the watch
//  describe the same colony the same way.
//

import SwiftUI
import FlowerPowerCore

enum Theme {

    // MARK: - Palette

    /// Honey golds, wax creams and the deep brown of a tree cavity.
    static let honey = Color(red: 0.93, green: 0.68, blue: 0.13)
    static let wax = Color(red: 0.96, green: 0.90, blue: 0.74)
    static let nectar = Color(red: 0.98, green: 0.82, blue: 0.35)
    static let pollen = Color(red: 0.94, green: 0.63, blue: 0.20)
    static let propolis = Color(red: 0.45, green: 0.28, blue: 0.12)
    static let comb = Color(red: 0.85, green: 0.72, blue: 0.42)
    static let broodNest = Color(red: 0.72, green: 0.50, blue: 0.24)

    static let queen = Color(red: 0.58, green: 0.34, blue: 0.71)
    static let worker = Color(red: 0.85, green: 0.65, blue: 0.16)
    static let drone = Color(red: 0.42, green: 0.42, blue: 0.46)

    static let alarm = Color(red: 0.82, green: 0.25, blue: 0.20)
    static let caution = Color(red: 0.90, green: 0.55, blue: 0.10)
    static let healthy = Color(red: 0.30, green: 0.62, blue: 0.36)

    // MARK: - Mappings

    static func colour(for kind: BeeKind) -> Color {
        switch kind {
        case .queen: return queen
        case .worker: return worker
        case .drone: return drone
        }
    }

    static func colour(for resource: ResourceKind) -> Color {
        switch resource {
        case .honey: return honey
        case .nectar: return nectar
        case .pollen: return pollen
        case .beeBread: return Color(red: 0.80, green: 0.55, blue: 0.25)
        case .royalJelly: return Color(red: 0.97, green: 0.95, blue: 0.88)
        case .wax: return wax
        case .propolis: return propolis
        case .water: return Color(red: 0.36, green: 0.65, blue: 0.85)
        }
    }

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

    /// Used to band the history charts, so a line can be read against the
    /// time of year it happened in. Deliberately muted: these are drawn behind
    /// the data and must never compete with it.
    static func colour(for season: Season) -> Color {
        switch season {
        case .spring: return Color(red: 0.55, green: 0.78, blue: 0.45)
        case .summer: return Color(red: 0.98, green: 0.82, blue: 0.35)
        case .autumn: return Color(red: 0.85, green: 0.55, blue: 0.25)
        case .winter: return Color(red: 0.55, green: 0.68, blue: 0.82)
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

    static func colour(for stage: DevelopmentStage) -> Color {
        switch stage {
        case .egg: return Color(red: 0.97, green: 0.96, blue: 0.90)
        case .larva: return Color(red: 0.95, green: 0.90, blue: 0.72)
        case .pupa: return Color(red: 0.80, green: 0.66, blue: 0.40)
        case .adult: return worker
        }
    }

    /// A milestone badge's face. Concrete `Color`s on both branches rather
    /// than `.quaternary` and friends, because a ternary of hierarchical
    /// styles has nothing for the compiler to infer a single type from.
    static func badgeFill(earned: Bool) -> AnyShapeStyle {
        earned
            ? AnyShapeStyle(honey.gradient)
            : AnyShapeStyle(Color.secondary.opacity(0.2))
    }

    /// The glyph on it.
    static func badgeGlyph(earned: Bool) -> AnyShapeStyle {
        earned ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.secondary)
    }

    // MARK: Symbols

    // The engine owns these now — see `Symbols.swift` in the package. They
    // were exhaustive switches over engine types living in a file no compiler
    // on the development machine can see, and two of them were a second and
    // third time over in `WatchTheme` and `WidgetTheme`. `Theme` keeps the
    // colours, because `Color` is SwiftUI and a palette is a house style in a
    // way that "a shield means defence" is not.

    static func symbol(for season: Season) -> String { season.symbolName }

    static func symbol(for sky: Sky) -> String { sky.symbolName }

    static func symbol(for resource: ResourceKind) -> String { resource.symbolName }

    static func symbol(for job: WorkerJob) -> String { job.symbolName }

    static func symbol(for predator: Predator) -> String { predator.symbolName }

    // MARK: - Layout

    static let cardCorner: CGFloat = 16
    static let cardPadding: CGFloat = 16
}

// MARK: - Reusable surfaces

/// The standard panel used throughout the app.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.cardPadding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cardCorner))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

/// A labelled horizontal bar, used for stores, readiness and health.
struct MeterView: View {

    let label: String
    let value: Double          // 0...1
    // `var` with an explicit default: a `let` optional gets no default in the
    // memberwise initialiser, which made `caption` accidentally mandatory.
    var caption: String? = nil
    var tint: Color = Theme.honey
    var symbolName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .foregroundStyle(tint)
                        .imageScale(.small)
                }
                Text(label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let caption {
                    Text(caption)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        // The label wraps; the number must not, or a reading
                        // at the accessibility sizes becomes "12 patri…".
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: geometry.size.width * min(1, max(0, value)))
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(caption ?? "\(Int(value * 100)) percent")
    }
}
