//
//  ColonyDashboardView.swift
//  FlowerPower
//
//  The screen that answers "how are my bees?" — and, when the answer is "not
//  well", says what to do about it.
//

import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

struct ColonyDashboardView: View {

    @Environment(GameStore.self) private var store
    var onPhotograph: () -> Void

    private var snapshot: ColonySnapshot { store.snapshot }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StatusHeader(snapshot: snapshot)

                    if !snapshot.alerts.isEmpty {
                        AlertsSection(alerts: snapshot.alerts)
                    }

                    StoresSection(stores: snapshot.stores, season: snapshot.season)
                    PopulationSection(population: snapshot.population)
                    QueenSection(queen: snapshot.queen)
                    NestConditionSection(nest: snapshot.nest)

                    if !snapshot.health.infections.isEmpty {
                        HealthSection(health: snapshot.health)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Colony")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onPhotograph) {
                        Label("Photograph a Flower", systemImage: "camera.fill")
                    }
                }
            }
        }
    }
}

// MARK: - Header

private struct StatusHeader: View {

    let snapshot: ColonySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(snapshot.status.displayName, systemImage: snapshot.status.symbolName)
                    .font(.headline)
                    .foregroundStyle(Theme.colour(for: snapshot.status))

                Spacer()

                Label(snapshot.season.displayName, systemImage: Theme.symbol(for: snapshot.season))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(snapshot.headline)
                .font(.title3.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                WeatherChip(weather: snapshot.weather)

                Label(
                    snapshot.isForaging ? "Foraging" : "In the nest",
                    systemImage: snapshot.isForaging ? "figure.walk.motion" : "house.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Text("Day \(snapshot.day)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct WeatherChip: View {

    let weather: Weather

    var body: some View {
        Label {
            Text("\(Int(weather.temperatureCelsius))°")
                .monospacedDigit()
        } icon: {
            Image(systemName: Theme.symbol(for: weather.sky))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel(
            "\(weather.sky.displayName), \(Int(weather.temperatureCelsius)) degrees"
        )
    }
}

// MARK: - Alerts

private struct AlertsSection: View {

    let alerts: [ColonyAlert]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(alerts) { alert in
                AlertRow(alert: alert)
                if alert.id != alerts.last?.id {
                    Divider()
                }
            }
        }
        .card()
    }
}

private struct AlertRow: View {

    let alert: ColonyAlert

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: alert.severity == .critical
                  ? "exclamationmark.triangle.fill"
                  : "exclamationmark.circle.fill")
                .foregroundStyle(Theme.colour(for: alert.severity))
                .imageScale(.large)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(alert.title)
                    .font(.subheadline.weight(.semibold))
                Text(alert.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let suggestion = alert.suggestion {
                    Text(suggestion)
                        .font(.caption.italic())
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Stores

private struct StoresSection: View {

    let stores: StoresSummary
    let season: Season

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Stores", systemImage: "archivebox.fill")

            // Winter readiness is the number that decides whether the colony
            // sees spring, so it leads from midsummer onward.
            if season == .summer || season == .autumn || season == .winter {
                MeterView(
                    label: "Winter Stores",
                    value: stores.winterReadiness,
                    caption: "\(Int(stores.edibleEnergy)) / \(Int(stores.winterRequirement))",
                    tint: stores.isWinterReady ? Theme.healthy : Theme.caution,
                    symbolName: "snowflake"
                )
            }

            let ordered = ResourceKind.allCases.filter { (stores.resources[$0] ?? 0) > 0.5 }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 88), spacing: 12)],
                spacing: 12
            ) {
                ForEach(ordered, id: \.self) { kind in
                    ResourceTile(kind: kind, amount: stores.resources[kind] ?? 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct ResourceTile: View {

    let kind: ResourceKind
    let amount: Double

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: Theme.symbol(for: kind))
                .foregroundStyle(Theme.colour(for: kind))
                .imageScale(.large)

            Text(amount, format: .number.precision(.fractionLength(0)))
                .font(.headline.monospacedDigit())

            Text(kind.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.displayName): \(Int(amount))")
    }
}

// MARK: - Population

private struct PopulationSection: View {

    let population: PopulationSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Population", systemImage: "person.3.fill")

            HStack(spacing: 0) {
                CountPill(value: population.total, label: "Total")
                CountPill(value: population.adults, label: "Adults")
                CountPill(value: population.brood, label: "Brood")
                CountPill(value: population.drones, label: "Drones")
            }

            BroodBar(population: population)

            if population.winterBees > 0 {
                Label(
                    "\(population.winterBees) winter bees — long-lived, and what carries the colony to spring",
                    systemImage: "snowflake"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            MeterView(
                label: "Condition",
                value: population.averageVitality,
                caption: String(format: "%.0f%%", population.averageVitality * 100),
                tint: population.averageVitality > 0.7 ? Theme.healthy : Theme.caution,
                symbolName: "heart.fill"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct CountPill: View {

    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Eggs, larvae and pupae as proportions — the shape of the brood nest tells an
/// experienced eye more than the total does.
private struct BroodBar: View {

    let population: PopulationSummary

    private var segments: [(stage: DevelopmentStage, count: Int)] {
        [(.egg, population.eggs), (.larva, population.larvae), (.pupa, population.pupae)]
            .filter { $0.1 > 0 }
    }

    var body: some View {
        let total = max(1, segments.reduce(0) { $0 + $1.count })

        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(segments, id: \.stage) { segment in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.colour(for: segment.stage))
                            .frame(
                                width: max(2, geometry.size.width
                                          * Double(segment.count) / Double(total) - 2)
                            )
                    }
                }
            }
            .frame(height: 10)

            HStack(spacing: 12) {
                ForEach(segments, id: \.stage) { segment in
                    Label("\(segment.count)", systemImage: "circle.fill")
                        .labelStyle(LegendLabelStyle(colour: Theme.colour(for: segment.stage)))
                        .font(.caption2)
                    Text(segment.stage.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Brood: \(population.eggs) eggs, \(population.larvae) larvae, \(population.pupae) pupae"
        )
    }
}

private struct LegendLabelStyle: LabelStyle {
    let colour: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .foregroundStyle(colour)
                .font(.system(size: 7))
            configuration.title
        }
    }
}

// MARK: - Queen

private struct QueenSection: View {

    let queen: QueenSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Queen", systemImage: "crown.fill")

            HStack {
                Text(queen.state.displayName)
                    .font(.headline)
                    .foregroundStyle(queen.state == .laying ? Theme.queen : Theme.alarm)
                Spacer()
                if queen.state != .absent {
                    Text("\(queen.ageDays) days old")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if queen.state == .laying || queen.state == .droneLayer {
                MeterView(
                    label: "Genetic Diversity",
                    value: queen.geneticDiversity,
                    caption: "\(queen.patrilines) patrilines",
                    tint: Theme.queen,
                    symbolName: "point.3.connected.trianglepath.dotted"
                )

                MeterView(
                    label: "Hygienic Behaviour",
                    value: queen.hygienicBehaviour,
                    caption: String(format: "%.0f%%", queen.hygienicBehaviour * 100),
                    tint: Theme.healthy,
                    symbolName: "sparkles"
                )

                Text("Diversity comes from how many drones she mated with. It is the colony's main defence against disease.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if queen.daysQueenless > 0 {
                Label("Queenless for \(queen.daysQueenless) days", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(Theme.alarm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Nest

private struct NestConditionSection: View {

    let nest: NestSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Nest", systemImage: "house.fill")

            HStack {
                Text(nest.siteType.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(nest.builtCells) / \(nest.capacity) cells")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            MeterView(
                label: "Comb Occupancy",
                value: nest.combOccupancy,
                caption: "\(nest.freeCells) free",
                tint: nest.combOccupancy > 0.9 ? Theme.caution : Theme.comb,
                symbolName: "hexagon.fill"
            )

            HStack(spacing: 20) {
                ReadingView(
                    symbol: "thermometer.medium",
                    value: String(format: "%.1f°C", nest.temperatureCelsius),
                    label: "Brood nest",
                    tint: abs(nest.temperatureCelsius - 35) < 2 ? Theme.healthy : Theme.caution
                )
                ReadingView(
                    symbol: "humidity.fill",
                    value: String(format: "%.0f%%", nest.humidity * 100),
                    label: "Humidity",
                    tint: Theme.colour(for: .water)
                )
                ReadingView(
                    symbol: "shield.lefthalf.filled",
                    value: String(format: "%.0f%%", nest.propolisEnvelope * 100),
                    label: "Propolis",
                    tint: Theme.propolis
                )
            }

            if !nest.queenCells.isEmpty {
                let names = Set(nest.queenCells.map(\.displayName)).sorted().joined(separator: ", ")
                Label("\(nest.queenCells.count) queen cells — \(names)", systemImage: "crown")
                    .font(.caption)
                    .foregroundStyle(Theme.queen)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct ReadingView: View {

    let symbol: String
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Health

private struct HealthSection: View {

    let health: HealthSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Health", systemImage: "cross.case.fill")

            ForEach(health.infections.sorted(by: { $0.value > $1.value }), id: \.key) { pathogen, level in
                MeterView(
                    label: pathogen.displayName,
                    value: level,
                    caption: String(format: "%.0f%%", level * 100),
                    tint: level > 0.5 ? Theme.alarm : Theme.caution,
                    symbolName: "microbe.fill"
                )
            }

            if health.infections[.varroa] != nil {
                Text("Varroa breeds in sealed brood and carries deformed wing virus. Hygienic bees uncap infested cells and remove them.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !health.recentAttacks.isEmpty {
                let names = Set(health.recentAttacks.map(\.displayName)).sorted().joined(separator: ", ")
                Label("Recent raids: \(names)", systemImage: "shield.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Shared

struct SectionTitle: View {

    let text: String
    let systemImage: String

    init(_ text: String, systemImage: String) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    ColonyDashboardView(onPhotograph: {})
        .environment(GameStore.preview())
}
