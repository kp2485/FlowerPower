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
//  It used to lead with all of them, in arrival order, up to sixty sentences
//  deep, which made the screen a wall: a fortnight away put the line saying
//  the queen was lost somewhere between two saying the weather turned, and
//  any chatty kind of event could fill the cap on its own. So the lines come
//  through `ReportDigest`, in the package, which groups them by what a player
//  would call them, counts each group, orders them by how much they matter
//  and caps each one separately. The screen opens as a headline, four
//  numbers, and a row per group that expands on a tap.
//

import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

struct CatchUpReportView: View {

    let report: CatchUpReport
    var onDismiss: () -> Void

    /// The grouping is the package's, done once when the sheet is built
    /// rather than on every redraw: it is a pass over up to sixty events, and
    /// this view redraws each time a group is opened.
    private let digest: ReportDigest

    init(report: CatchUpReport, onDismiss: @escaping () -> Void) {
        self.report = report
        self.onDismiss = onDismiss
        digest = ReportDigest(report: report)
    }

    @Environment(GameStore.self) private var store

    /// Flipped once, on appearing, when the report carries a milestone. The
    /// trigger form never plays on its initial value, so this is the change
    /// from false that plays — and it cannot play twice for one report.
    @State private var reachedSomething = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Header(report: report, headline: store.snapshot.headline)

                    PopulationChangeCard(report: report)

                    if !digest.isEmpty {
                        HighlightsCard(digest: digest)
                    }

                    // The raids and the infections have their own cards
                    // still, because a count of stores taken and a pathogen's
                    // name are figures the digest's sentences do not carry.
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
            // A first is the one thing in a catch-up report that is
            // unambiguously good news, which is what makes it the only thing
            // here worth a tap.
            .sensoryFeedback(.success, trigger: reachedSomething)
            .onAppear {
                if !report.milestones.isEmpty { reachedSomething = true }
            }
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

    let digest: ReportDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle("What happened", systemImage: "sparkles")
                .padding(.bottom, 6)

            ForEach(digest.groups) { group in
                HighlightGroupRow(group: group)

                if group.id != digest.groups.last?.id {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// One heading, shut: a dot for how bad it is, the heading, and the count.
/// Open: the sentences behind it, capped, with a line saying what is left.
private struct HighlightGroupRow: View {

    let group: ReportDigest.Group

    /// The gravest group opens by itself. The one thing this screen must not
    /// do is make a player tap to find out their colony collapsed.
    @State private var isExpanded: Bool

    init(group: ReportDigest.Group) {
        self.group = group
        _isExpanded = State(initialValue: group.severity >= .critical)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.visibleLines) { line in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Theme.colour(for: line.severity))
                            .frame(width: 7, height: 7)
                            .padding(.top, 6)
                            .accessibilityHidden(true)

                        Text(line.display)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }

                if let overflow = group.overflowLine {
                    Text(overflow)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 17)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
        } label: {
            HStack(spacing: 10) {
                // The heading's own symbol, tinted by the worst thing under
                // it — so the row says what kind of news it is and how bad
                // it is without being read.
                Image(systemName: group.category.symbolName)
                    .foregroundStyle(Theme.colour(for: group.severity))
                    .imageScale(.small)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                Text(group.category.displayName)
                    .font(.subheadline.weight(.medium))

                Spacer(minLength: 8)

                Text(group.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(group.category.displayName)
            .accessibilityValue(group.summary)
            .accessibilityHint(isExpanded ? "Collapses the lines" : "Expands the lines")
        }
        .tint(Theme.honey)
        .sensoryFeedback(.selection, trigger: isExpanded)
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

            // The causes of death, folded away. Nine rows of them under four
            // figures is the sort of thing that makes this screen a wall,
            // and the answer a player wants — how many, and did it grow — is
            // already above. The breakdown is for the one morning in ten
            // when it is not.
            if !report.died.isEmpty {
                DisclosureGroup {
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
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text("What they died of")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .accessibilityHint("Expands the causes of death")
                }
                .tint(Theme.honey)
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
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
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
