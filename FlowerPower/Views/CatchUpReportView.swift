//
//  CatchUpReportView.swift
//  FlowerPower
//
//  What happened while you were away.
//
//  This is the payoff screen of an idle game, and it has one job: make the time
//  the player was not looking feel like it mattered. So it leads with the
//  events — a swarm, a new queen, a raid — and treats the raw counts of births
//  and deaths as background.
//

import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

struct CatchUpReportView: View {

    let report: CatchUpReport
    var onDismiss: () -> Void

    @Environment(GameStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Header(report: report, headline: store.snapshot.headline)

                    if !report.highlights.isEmpty {
                        HighlightsCard(events: report.highlights)
                    }

                    PopulationChangeCard(report: report)

                    if report.storesRaided > 0 || !report.attacks.isEmpty {
                        RaidsCard(report: report)
                    }

                    if !report.newInfections.isEmpty || !report.criticalInfections.isEmpty {
                        InfectionsCard(report: report)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("While You Were Away")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }
}

// MARK: - Sections

private struct Header: View {

    let report: CatchUpReport
    let headline: String

    var body: some View {
        VStack(spacing: 8) {
            Text(elapsedDescription)
                .font(.title3.weight(.semibold))
            Text(headline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private var elapsedDescription: String {
        let days = report.daysSimulated
        if days >= 2 { return "\(days) days passed in the hive" }
        if days == 1 { return "A day passed in the hive" }
        return "A few hours passed"
    }
}

private struct HighlightsCard: View {

    let events: [SimEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("What happened", systemImage: "sparkles")

            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Theme.colour(for: event.severity))
                        .frame(width: 7, height: 7)
                        .padding(.top, 6)

                    Text(event.narration)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct PopulationChangeCard: View {

    let report: CatchUpReport

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("The colony", systemImage: "person.3.fill")

            HStack {
                Stat(value: report.eggsLaid, label: "Eggs laid", tint: Theme.colour(for: .egg))
                Stat(value: report.totalEmerged, label: "Emerged", tint: Theme.healthy)
                Stat(value: report.totalDeaths, label: "Died", tint: Theme.alarm)
                Stat(value: report.cellsBuilt, label: "Cells built", tint: Theme.comb)
            }

            let net = report.netPopulationChange
            Label(
                net >= 0 ? "The colony grew by \(net)" : "The colony shrank by \(-net)",
                systemImage: net >= 0 ? "arrow.up.right" : "arrow.down.right"
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(net >= 0 ? Theme.healthy : Theme.caution)

            if !report.died.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(report.died.sorted(by: { $0.value > $1.value }), id: \.key) { cause, count in
                        HStack {
                            Text(cause.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct Stat: View {

    let value: Int
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

private struct RaidsCard: View {

    let report: CatchUpReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Raids", systemImage: "shield.slash.fill")

            let counts = Dictionary(grouping: report.attacks, by: { $0 }).mapValues(\.count)
            ForEach(counts.sorted(by: { $0.value > $1.value }), id: \.key) { predator, count in
                Label(
                    count > 1 ? "\(predator.displayName) ×\(count)" : predator.displayName,
                    systemImage: Theme.symbol(for: predator)
                )
                .font(.subheadline)
            }

            if report.storesRaided > 0 {
                Text("\(Int(report.storesRaided)) of stores taken.")
                    .font(.caption)
                    .foregroundStyle(Theme.alarm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct InfectionsCard: View {

    let report: CatchUpReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Health", systemImage: "cross.case.fill")

            ForEach(Array(Set(report.newInfections)), id: \.self) { pathogen in
                Label("\(pathogen.displayName) appeared", systemImage: "microbe.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.caution)
            }

            ForEach(Array(Set(report.criticalInfections)), id: \.self) { pathogen in
                Label("\(pathogen.displayName) is now critical", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.alarm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// The sentence for each event lives in the package, as
// `SimEvent.narration`. It was here, in a target nothing on this machine
// can compile, and had gone non-exhaustive when the engine gained the
// decision events. See EventNarration.swift.
