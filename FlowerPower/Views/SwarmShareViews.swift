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
                        LabeledContent("Honey carried", value: "\(Int(swarm.honeyCarried.rounded())) units")
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
                        ShareLink(item: prepared) {
                            Label("Send the Swarm", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.honey)
                        .controlSize(.large)
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
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(share.queenTitle).\(SwarmShare.fileExtension)")
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
                        LabeledContent("Honey in their crops", value: "\(Int(share.honeyCarried.rounded())) units")
                        LabeledContent("Mated with", value: "\(share.genetics.patrilines) drones")
                    }
                    .font(.subheadline)
                    .card()

                    Text(store.isCollapsed
                         ? "Your last colony is gone. This swarm can be the next."
                         : "Taking this swarm replaces your current colony. Your garden stays.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if adopted {
                        Label("Settled", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.healthy)
                    } else {
                        Button {
                            if store.isCollapsed { isChoosingSite = true } else { isConfirmingReplace = true }
                        } label: {
                            Label("Give Them a Home", systemImage: "hexagon.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.honey)
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
