//
//  ShareFlowerView.swift
//  FlowerPower
//
//  Sending a flower to somebody.
//
//  Almost everything in a share is decided by the game: which species, how
//  sure the identification was, when it was photographed. The only parts a
//  person chooses are the two on this screen — a name to be thanked by and a
//  line to read alongside the flower — so the form is short, and most of it
//  is there to show what is about to go before the share sheet opens.
//
//  Nothing here asks about place. A share carries no location at all, because
//  the app never learns one, and the photograph's own EXIF is left behind when
//  the picture is re-encoded on the way out. That means there is no setting
//  for a player to remember to switch off, and no way for a flower sent to a
//  group chat to tell everyone in it where somebody was standing. The
//  re-encode is in `SharedImageStore.prepareForSharing`.
//

import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

struct ShareFlowerView: View {

    let patch: PatchSummary

    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @AppStorage("shareSenderName") private var senderName = ""
    @State private var note = ""
    @State private var image: UIImage?
    @State private var prepared: URL?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        PhotoThumbnail(localIdentifier: patch.photoLocalIdentifier)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(patch.speciesName)
                                .font(.headline)
                            Text(patch.isIdentified
                                 ? "Your friend's bees will know what it is."
                                 : "Unnamed, which their bees do not mind.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
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
                            Label("Send Flower", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.honey)
                        .controlSize(.large)
                    } else {
                        HStack {
                            Spacer()
                            ProgressView()
                                .accessibilityLabel("Preparing the flower to send")
                            Spacer()
                        }
                    }
                } footer: {
                    if let failure {
                        Text(failure).foregroundStyle(Theme.alarm)
                    } else {
                        Text("They can open it in FlowerPower and their bees will work it, exactly as yours do.")
                    }
                }
            }
            .navigationTitle("Share a Flower")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        // Rebuilt whenever anything that goes into the file changes, so the
        // share sheet can never hand over a stale one — signed with a name the
        // player has since corrected, or missing the line they just typed.
        .task(id: rebuildKey) { @MainActor in
            await prepare()
        }
    }

    private var rebuildKey: String {
        "\(senderName)|\(note)"
    }

    @MainActor
    private func prepare() async {
        prepared = nil
        failure = nil

        let source: UIImage?
        if let image {
            source = image
        } else {
            source = await loadFullImage()
            image = source
        }

        guard let source, let data = SharedImageStore.prepareForSharing(source) else {
            failure = "That photograph could not be prepared to send."
            return
        }

        guard let share = store.share(
            patch: patch.id,
            imageData: data,
            from: senderName.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        ) else {
            failure = "That flower is no longer in your garden."
            return
        }

        do {
            prepared = try SharedImageStore.temporaryFile(for: share)
        } catch {
            failure = error.localizedDescription
        }
    }

    private func loadFullImage() async -> UIImage? {
        if let shared = SharedImageStore.image(forLocalIdentifier: patch.photoLocalIdentifier) {
            return shared
        }
        return await PhotoLibrary.thumbnail(
            for: patch.photoLocalIdentifier,
            size: CGSize(width: 1_600, height: 1_600)
        )
    }
}
