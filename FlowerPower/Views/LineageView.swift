//
//  LineageView.swift
//  FlowerPower
//
//  The line of queens.
//
//  A colony's legacy is not a score, it is this: who reigned, for how long,
//  how it ended, and whose daughter she was. The names are the player's to
//  give.
//

import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

struct LineageView: View {

    @Environment(GameStore.self) private var store
    @State private var naming: QueenRecord?
    @State private var draftName = ""
    /// Naming a queen is the one thing the player can do on this screen, so
    /// it is worth feeling. Counted so a second naming lands too.
    @State private var namings = 0

    private var lineage: Lineage { store.snapshot.lineage }
    private var today: Int { store.snapshot.day }

    var body: some View {
        List {
            Section {
                LabeledContent("Colony", value: "Generation \(lineage.generation)")
                LabeledContent("Queens", value: "\(lineage.count)")
                if let reigning = lineage.reigning {
                    LabeledContent("Reigning", value: reigning.title)
                }
            }

            Section("The line") {
                ForEach(lineage.queens.reversed()) { queen in
                    Button {
                        naming = queen
                        draftName = queen.name ?? ""
                    } label: {
                        QueenRow(queen: queen, today: today, lineage: lineage)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Tap to name her")
                }
            }
        }
        .navigationTitle("Lineage")
        .sensoryFeedback(.success, trigger: namings)
        .sheet(item: $naming) { queen in
            NavigationStack {
                Form {
                    Section {
                        TextField("Name", text: $draftName)
                            .textInputAutocapitalization(.words)
                    } header: {
                        Text("Name \(QueenRecord(number: queen.number, motherNumber: nil, emergedOnDay: 0).title)")
                    } footer: {
                        Text("Leave it empty to go back to her number.")
                    }
                }
                .navigationTitle("Name a Queen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { naming = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            store.nameQueen(queen.number, draftName)
                            namings += 1
                            naming = nil
                        }
                    }
                }
            }
        }
    }
}

private struct QueenRow: View {

    let queen: QueenRecord
    let today: Int
    let lineage: Lineage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "crown.fill")
                    .foregroundStyle(queen.isReigning ? Theme.queen : .secondary)
                    .accessibilityHidden(true)
                Text(queen.title)
                    .font(.headline)
                Spacer()
                if queen.isReigning {
                    Text("Reigning")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.queen)
                }
            }

            Text(parentage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(reign)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let ending = queen.ending {
                Text(ending.displayName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var parentage: String {
        guard let mother = queen.motherNumber,
              let record = lineage.queens.first(where: { $0.number == mother })
        else { return "Founding queen" }
        return "Daughter of \(record.title)"
    }

    private var reign: String {
        let days = queen.reignDays(on: today)
        let mated = queen.patrilines.map { "mated with \($0) drones" } ?? "unmated"
        return "Reigned \(days) days, \(mated)"
    }
}
