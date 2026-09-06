//
//  ShareFlowerView.swift
//  FlowerPower
//
//  Sending a flower to somebody.
//
//  The screen exists mostly for one control. Everything else here could have
//  been a single share button, but a flower photograph knows where it was
//  taken, and that is where a person was standing — often their garden, which
//  is their address. So the location choice is on the screen, set to not
//  sharing, rather than buried in settings where the default would quietly
//  become whatever it was left at.
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
    @State private var location: LocationSharing = .none
    @State private var image: UIImage?
    @State private var prepared: URL?
    @State private var failure: String?

    /// Location choices only make sense for a flower that has one.
    private var hasLocation: Bool { patch.coordinate != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        PhotoThumbnail(localIdentifier: patch.photoLocalIdentifier)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

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
                }

                Section("From") {
                    TextField("Your name", text: $senderName)
                        .textInputAutocapitalization(.words)
                    TextField("Say something (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                if hasLocation {
                    Section {
                        Picker("Location", selection: $location) {
                            ForEach(LocationSharing.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } header: {
                        Text("Where You Found It")
                    } footer: {
                        Text(location.detail)
                    }
                } else {
                    Section {
                        Label(
                            "This photo has no location, so none will be sent.",
                            systemImage: "location.slash"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
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
        // share sheet can never hand over a stale one — in particular one
        // carrying a location the player has since switched off.
        .task(id: rebuildKey) { @MainActor in
            await prepare()
        }
    }

    private var rebuildKey: String {
        "\(location.rawValue)|\(senderName)|\(note)"
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
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            location: location
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
