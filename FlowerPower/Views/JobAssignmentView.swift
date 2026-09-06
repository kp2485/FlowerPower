//
//  JobAssignmentView.swift
//  FlowerPower
//
//  Features.md asked for sliders assigning bees to jobs. This is that, with one
//  correction the simulation forced: you cannot simply move bees between jobs.
//
//  A worker's job follows her age. A three-day-old bee physically cannot
//  forage — she has no wax glands worn down yet, no orientation flights, and
//  her body is still building. So the player is not allocating a pool of
//  interchangeable workers; they are nudging a colony that already knows what
//  it is doing, and only within what each bee is capable of.
//
//  That constraint is more interesting than the slider would have been. It
//  means the real lever is *which bees exist*, and that comes back to forage.
//

import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

struct JobAssignmentView: View {

    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var emphasis: WorkerJob?

    private var population: PopulationSummary { store.snapshot.population }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Bees take on work as they age. You can lean the colony toward a job, but only bees old enough — and well enough — will take it up.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section("Current workforce") {
                    ForEach(orderedJobs, id: \.job) { entry in
                        JobRow(
                            job: entry.job,
                            count: entry.count,
                            maximum: maximumCount,
                            isEmphasised: emphasis == entry.job
                        ) {
                            toggleEmphasis(entry.job)
                        }
                    }
                }

                if emphasis != nil {
                    Section {
                        Button("Let the colony decide", role: .destructive) {
                            emphasis = nil
                            store.clearAllAssignments()
                        }
                    } footer: {
                        Text("Clears every assignment and returns the colony to its natural division of labour.")
                    }
                }

                Section {
                    ForEach(WorkerJob.allCases, id: \.self) { job in
                        HStack {
                            Image(systemName: Theme.symbol(for: job))
                                .frame(width: 24)
                                .foregroundStyle(Theme.worker)
                            Text(job.displayName)
                                .font(.subheadline)
                            Spacer()
                            Text("days \(job.adultAgeRange.lowerBound)–\(job.adultAgeRange.upperBound - 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("The age ladder")
                } footer: {
                    Text("Winter bees are the exception: they never wore themselves out, so they can turn a hand to anything the colony needs in spring.")
                }
            }
            .navigationTitle("Jobs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var orderedJobs: [(job: WorkerJob, count: Int)] {
        WorkerJob.allCases
            .map { (job: $0, count: population.jobs[$0] ?? 0) }
            .sorted { $0.count > $1.count }
    }

    private var maximumCount: Int {
        max(1, population.jobs.values.max() ?? 1)
    }

    /// Pins every capable bee to one job, or releases them all.
    private func toggleEmphasis(_ job: WorkerJob) {
        if emphasis == job {
            emphasis = nil
            store.clearAllAssignments()
        } else {
            emphasis = job
            store.emphasise(job)
        }
    }
}

private struct JobRow: View {

    let job: WorkerJob
    let count: Int
    let maximum: Int
    let isEmphasised: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: Theme.symbol(for: job))
                        .frame(width: 24)
                        .foregroundStyle(isEmphasised ? Theme.honey : Theme.worker)

                    Text(job.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Spacer()

                    if isEmphasised {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.honey)
                    }

                    Text("\(count)")
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geometry in
                    Capsule()
                        .fill(isEmphasised ? Theme.honey : Theme.worker.opacity(0.35))
                        .frame(width: geometry.size.width * Double(count) / Double(maximum))
                }
                .frame(height: 4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.displayName), \(count) bees")
        .accessibilityHint(isEmphasised ? "Tap to release" : "Tap to prioritise this job")
        .accessibilityAddTraits(isEmphasised ? [.isSelected] : [])
    }
}

#Preview {
    JobAssignmentView()
        .environment(GameStore.preview())
}
