//
//  RequestViews.swift
//  FlowerPower
//
//  Asking a friend for forage, and answering when one asks you.
//
//  A colony short of what is flowering can send a request: a small file that,
//  opened by a friend, says what the bees are short of and offers the garden
//  filtered to it. It is the same file a flower travels in, with no
//  photograph and a list of families instead.
//

import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

// MARK: - Asking

struct AskForForageView: View {

    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @AppStorage("shareSenderName") private var senderName = ""
    @State private var note = ""
    @State private var prepared: URL?
    @State private var request: FlowerShare?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let request, let wanted = request.wanted, !wanted.isEmpty {
                        ForEach(wanted, id: \.self) { family in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(family.commonName).font(.subheadline)
                                Text(family.forageNote).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Your garden has something workable in every family flowering now. Nothing to ask for.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Short of")
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
                            Label("Ask a Friend", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.honey)
                        .controlSize(.large)
                    }
                } footer: {
                    Text("They open it in FlowerPower and see which of their flowers would help.")
                }
            }
            .navigationTitle("Ask for Forage")
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
        let built = store.forageRequest(
            from: senderName.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        request = built
        prepared = try? SharedImageStore.temporaryFile(for: built)
    }
}

// MARK: - Answering

struct ReceiveRequestView: View {

    let request: FlowerShare

    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var sharing: PatchSummary?

    /// The player's flowers that would help: in the wanted families, and
    /// still worth something.
    private var candidates: [PatchSummary] {
        let wanted = Set(request.wanted ?? [])
        return store.snapshot.patches
            .filter { patch in
                guard let family = patch.family else { return false }
                return (wanted.isEmpty || wanted.contains(family)) && !patch.hasFaded
            }
            .sorted { $0.vigour > $1.vigour }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(request.requestSummary)
                        .font(.headline)
                    if let note = request.note {
                        Text("\u{201C}\(note)\u{201D}")
                            .font(.callout).italic()
                            .foregroundStyle(.secondary)
                    }
                    if let season = request.season {
                        Label("Their colony is in \(season.rawValue).", systemImage: Theme.symbol(for: season))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if candidates.isEmpty {
                        Text("Nothing in your garden would help right now.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(candidates) { patch in
                            Button {
                                sharing = patch
                            } label: {
                                HStack {
                                    PhotoThumbnail(localIdentifier: patch.photoLocalIdentifier)
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading) {
                                        Text(patch.speciesName).font(.subheadline)
                                        if let family = patch.family {
                                            Text(family.commonName).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "square.and.arrow.up")
                                        .foregroundStyle(Theme.honey)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Flowers of yours that would help")
                }
            }
            .navigationTitle("A Friend Asks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
            .sheet(item: $sharing) { patch in
                ShareFlowerView(patch: patch)
            }
        }
    }
}
