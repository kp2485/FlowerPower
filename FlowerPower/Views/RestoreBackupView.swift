//
//  RestoreBackupView.swift
//  FlowerPower
//
//  Opening a backup, and deciding whether to put it back.
//
//  This screen exists because restoring is the most destructive thing in the
//  game and the only one that can be triggered from outside it. A `.flower`
//  adds a patch and a `.swarm` founds a colony; a `.flowerhive` *replaces* the
//  colony, the garden and the lineage with whatever is in the file. A tap on a
//  file in a message thread must therefore not restore anything — it can only
//  offer to.
//
//  So the screen's job is to say what is in the file and what is currently on
//  the phone, side by side, and let the player compare them. Two backups a
//  year apart look identical in a Files listing, and the wrong one is not
//  recoverable.
//

import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

/// What came of opening a `.flowerhive`: a colony, or a reason there is none.
///
/// Both cases go to the same screen rather than one to a sheet and the other
/// to an alert, because a failed decode of a backup is exactly the moment a
/// player needs telling that their colony has *not* been touched — which an
/// alert saying only "could not be opened" does not say.
enum OpenedBackup: Identifiable {
    case archive(SaveArchive)
    case failure(String)

    var id: String {
        switch self {
        case .archive(let archive): return archive.id
        case .failure(let reason): return reason
        }
    }
}

struct RestoreBackupView: View {

    let opened: OpenedBackup

    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirming = false

    var body: some View {
        NavigationStack {
            Group {
                switch opened {
                case .archive(let archive):
                    form(for: archive)
                case .failure(let reason):
                    unreadable(reason)
                }
            }
            .navigationTitle("A Colony Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - A backup that can be read

    private func form(for archive: SaveArchive) -> some View {
        // Hoisted out of the body: `summary` computes a whole `ColonySnapshot`
        // every time it is read, and reading it once per row would do that six
        // times on every redraw.
        let summary = archive.summary

        return Form {
            Section {
                LabeledContent("Taken", value: archive.exportedAt.formatted(
                    date: .abbreviated, time: .shortened
                ))
                LabeledContent("Colony", value: summary.status.displayName)
                LabeledContent("Day", value: "\(summary.day + 1)")
                LabeledContent("Season", value: summary.season.rawValue.capitalized)
                LabeledContent("Bees", value: "\(summary.beeCount)")
                LabeledContent("Flowers", value: "\(summary.flowerCount)")
                if summary.photographCount > 0 {
                    LabeledContent("Photographs", value: "\(summary.photographCount)")
                }
                if summary.generation > 1 {
                    LabeledContent("Generation", value: "\(summary.generation)")
                }
            } header: {
                Text("In the Backup")
            }

            // On a first run there is nothing to compare it with. What the
            // store holds then is a placeholder nobody chose, and this screen
            // used to offer it up as "200 bees" the player was about to lose.
            if store.needsSetup {
                Section {
                    Button("Restore This Colony") { restore(archive) }
                } footer: {
                    Text(pickingUp(archive))
                }
            } else {
                Section {
                    LabeledContent("Colony", value: store.snapshot.status.displayName)
                    LabeledContent("Day", value: "\(store.snapshot.displayDay)")
                    LabeledContent("Bees", value: "\(store.snapshot.population.total)")
                    LabeledContent("Flowers", value: "\(store.snapshot.patches.count)")
                } header: {
                    Text("On This Phone")
                } footer: {
                    Text("Restoring replaces all of it — the colony, the comb, the queens and the flowers in your garden — with what is in the backup. " + pickingUp(archive) + " There is no undo.")
                }

                Section {
                    Button("Restore This Colony", role: .destructive) {
                        isConfirming = true
                    }
                } footer: {
                    if let version = archive.appVersion {
                        Text("Written by FlowerPower \(version).")
                    }
                }
            }

        }
        .confirmationDialog(
            "Replace this phone's colony?",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) { restore(archive) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The colony on this phone will be gone. If you might want it back, export a backup of it first.")
        }
    }

    /// What happens to the pictures, which depends on whether the file
    /// brought any.
    private func pickingUp(_ archive: SaveArchive) -> String {
        if archive.photographCount > 0 {
            return "It picks up from the day it was saved, and the photographs in the file come with it: the garden shows them from the backup wherever the originals are."
        }
        return "It picks up from the day it was saved. This backup carries no photographs, so a flower photographed on another phone arrives with a blank thumbnail."
    }

    private func restore(_ archive: SaveArchive) {
        // The pictures first, so a flower is never on screen before its
        // photograph is in place to be shown. Kept under the identifier the
        // patch carries: Photos on this phone knows nothing by that name, and
        // the loader looks here next.
        for photograph in archive.validatedPhotographs() {
            SharedImageStore.keep(photograph.jpeg, forIdentifier: photograph.identifier)
        }
        store.restore(from: archive)
        dismiss()
    }

    // MARK: - A backup that cannot

    private func unreadable(_ reason: String) -> some View {
        Form {
            Section {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.alarm)
            } footer: {
                Text("Nothing has changed. The colony on this phone is exactly as it was.")
            }
        }
    }
}

// MARK: - Preview

#Preview("A backup") {
    RestoreBackupView(opened: .archive(SaveArchive.preview()))
        .environment(GameStore.preview())
}

#Preview("One that cannot be read") {
    RestoreBackupView(
        opened: .failure(SaveArchive.Failure.notASaveFile.localizedDescription)
    )
    .environment(GameStore.preview())
}
