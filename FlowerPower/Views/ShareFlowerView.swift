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
//  the app never learns one, and the photograph's own metadata is stripped
//  on the way out. That means there is no setting for a player to remember
//  to switch off, and no way for a flower sent to a group chat to tell
//  everyone in it where somebody was standing. The stripping is
//  `SharedImageStore.prepareForSharing`, which also keeps the picture at the
//  size it was taken as far as the file cap allows, and passes a friend's
//  flower on pixel for pixel rather than compressing it a second time.
//
//  The picture is prepared once, off the main actor, when the screen opens;
//  a name or a note being typed only rewrites the small file around it.
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
    /// The photograph made fit to send, loaded once; every rebuild of the
    /// file waits on this rather than redoing it.
    @State private var picture: Task<Data?, Never>?
    /// A small copy for the share sheet's header, so Messages shows the
    /// flower rather than a document icon.
    @State private var preview: UIImage?
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
                        ShareLink(item: prepared, preview: sharePreview) {
                            Label("Send Flower", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.honey)
                        .foregroundStyle(Theme.onHoney)
                        .controlSize(.large)
                    } else if failure == nil {
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
        // The stale file is withdrawn at once so it cannot be sent.
        .task(id: rebuildKey) { @MainActor in
            prepared = nil
            await prepare()
        }
    }

    private var sharePreview: SharePreview<Image, Never> {
        // A symbol until the picture is ready, so the header always has an
        // image rather than the file type's blank document icon.
        SharePreview(
            patch.speciesName,
            image: preview.map { Image(uiImage: $0) } ?? Image(systemName: "camera.macro")
        )
    }

    private var rebuildKey: String {
        "\(senderName)|\(note)"
    }

    @MainActor
    private func prepare() async {
        prepared = nil
        failure = nil

        if picture == nil {
            let identifier = patch.photoLocalIdentifier
            picture = Task { await Self.pictureToSend(for: identifier) }
        }
        guard let data = await picture?.value else {
            failure = "That photograph is not on this phone, so it cannot be sent."
            return
        }
        guard !Task.isCancelled else { return }
        if preview == nil {
            preview = await Self.thumbnail(of: data)
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

    /// The photograph's own bytes, made fit to send. Off the main actor:
    /// re-encoding a camera original is real work, and done on the main
    /// thread it made typing a name lag.
    @concurrent
    nonisolated private static func pictureToSend(for identifier: String) async -> Data? {
        guard let original = await PhotoLoader.originalData(for: identifier) else { return nil }
        return SharedImageStore.prepareForSharing(original)
    }

    @concurrent
    nonisolated private static func thumbnail(of data: Data) async -> UIImage? {
        PhotoLibrary.workingImage(from: data, maxPixelSize: 320)
    }
}
