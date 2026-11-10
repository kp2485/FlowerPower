//
//  SwarmShareViews.swift
//  FlowerPowerGame
//
//  Giving a swarm away, and taking one in.
//
//  When a colony swarms, the old queen and most of the bees leave with no
//  home. Catching that swarm is how most beekeepers get their second colony;
//  giving it to a friend is the same thing at one remove. The recipient founds
//  a colony from it at a site they choose, with the queen's number and name
//  intact.
//

import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

// MARK: - Giving

struct ShareSwarmView: View {

    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @AppStorage("shareSenderName") private var senderName = ""
    @State private var note = ""
    @State private var prepared: URL?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                if let swarm = store.snapshot.departedSwarm {
                    Section {
                        LabeledContent("Queen", value: swarm.queenTitle)
                        LabeledContent("Bees", value: "\(swarm.beeCount)")
                        LabeledContent("Honey carried", value: Int(swarm.honeyCarried.rounded()).counted("unit"))
                    } footer: {
                        Text("Your friend will found a colony from this swarm at a site they choose. Your colony keeps its virgin queen either way.")
                    }
                }

                Section("From") {
                    TextField("Your name", text: $senderName)
                        .textInputAutocapitalization(.words)
                    TextField("Say something (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    if let prepared {
                        ShareLink(
                            item: prepared,
                            preview: SharePreview(
                                "A swarm from \(store.snapshot.departedSwarm?.queenTitle ?? "the hive")",
                                image: Image(systemName: "wind")
                            )
                        ) {
                            Label("Send the Swarm", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.honey)
                        .foregroundStyle(Theme.onHoney)
                        .controlSize(.large)

                        // A share sheet cannot say whether anything was sent,
                        // so the player says. Without this the swarm stayed
                        // theirs to follow or give away again.
                        Button("I've Sent It") {
                            store.letSwarmGo()
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                } footer: {
                    if let failure { Text(failure).foregroundStyle(Theme.alarm) }
                }
            }
            .navigationTitle("Give the Swarm Away")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: "\(senderName)|\(note)") { @MainActor in
                prepare()
            }
        }
    }

    @MainActor
    private func prepare() {
        prepared = nil
        failure = nil
        guard let share = store.shareSwarm(
            from: senderName.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        ) else {
            failure = "There is no swarm to give."
            return
        }
        do {
            // The title carries the queen's name, which the player typed. A
            // "/" in it made a path into a folder that does not exist, and
            // the share failed; ":" and a leading "." misbehave in Files too.
            let safeTitle = share.queenTitle
                .map { "/:\\".contains($0) ? "-" : $0 }
                .reduce(into: "") { $0.append($1) }
                .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(safeTitle.isEmpty ? "Swarm" : safeTitle).\(SwarmShare.fileExtension)")
            try share.encoded().write(to: url, options: .atomic)
            prepared = url
        } catch {
            failure = error.localizedDescription
        }
    }
}

// MARK: - Receiving

struct ReceiveSwarmView: View {

    let share: SwarmShare

    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var isChoosingSite = false
    @State private var isConfirmingReplace = false
    @State private var adopted = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "bird.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.queen)
                        .accessibilityHidden(true)

                    VStack(spacing: 6) {
                        Text("A swarm for you")
                            .font(.title2.weight(.semibold))
                        if let sender = share.sharedBy {
                            Text("Sent by \(sender)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let note = share.note {
                        Text("\u{201C}\(note)\u{201D}")
                            .font(.callout).italic()
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Queen", value: share.queenTitle)
                        LabeledContent("Bees", value: "\(share.workerCount)")
                        LabeledContent("Honey in their crops", value: Int(share.honeyCarried.rounded()).counted("unit"))
                        LabeledContent("Mated with", value: share.genetics.patrilines.counted("drone"))
                    }
                    .font(.subheadline)
                    .card()

                    if !adopted {
                        Text(store.needsSetup
                             ? "This swarm can be your first colony."
                             : store.isCollapsed
                                ? "Your last colony is gone. This swarm can be the next."
                                : "Taking this swarm replaces your current colony. Your garden stays.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if adopted {
                        Label("Settled", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.healthy)
                    } else {
                        Button {
                            // Nothing to replace before the first site is chosen:
                            // the colony the store holds then is a placeholder.
                            if store.isCollapsed || store.needsSetup {
                                isChoosingSite = true
                            } else {
                                isConfirmingReplace = true
                            }
                        } label: {
                            Label("Give Them a Home", systemImage: "hexagon.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.honey)
                        .foregroundStyle(Theme.onHoney)
                        .controlSize(.large)
                    }
                }
                .padding()
            }
            .navigationTitle("A Swarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(adopted ? "Done" : "Not Now") { dismiss() }
                }
            }
            .confirmationDialog(
                "Replace your colony?", isPresented: $isConfirmingReplace, titleVisibility: .visible
            ) {
                Button("Replace It", role: .destructive) { isChoosingSite = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your current colony and everything it has built will be gone. Your flowers stay.")
            }
            .sheet(isPresented: $isChoosingSite) {
                NewColonyView(reason: .firstColony) { site in
                    store.adoptSwarm(share, at: HiveLocation(type: site))
                    adopted = true
                    isChoosingSite = false
                }
            }
        }
    }
}
