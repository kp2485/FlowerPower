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
//  Each queen's row opens. Shut, it is her title, whose daughter she is and
//  how long she has had; open, it is her whole record — when she emerged, her
//  mating flight, the daughters she left, how it ended. That detail was
//  crammed into four lines of grey caption on every row at once, which made a
//  line of six queens a page of small print. Naming her is a hold, and a
//  button inside the opened record.
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
                    QueenRow(
                        queen: queen,
                        today: today,
                        lineage: lineage,
                        onName: { startNaming(queen) }
                    )
                    .contextMenu {
                        Button("Name Her", systemImage: "square.and.pencil") {
                            startNaming(queen)
                        }
                        if queen.name != nil {
                            Button("Back to Her Number", systemImage: "arrow.uturn.backward") {
                                store.nameQueen(queen.number, nil)
                                namings += 1
                            }
                        }
                    }
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

    private func startNaming(_ queen: QueenRecord) {
        naming = queen
        draftName = queen.name ?? ""
    }
}

/// One queen, shut and open.
private struct QueenRow: View {

    let queen: QueenRecord
    let today: Int
    let lineage: Lineage
    var onName: () -> Void

    /// The reigning queen's record is the one a player came to look at, so it
    /// is the one already open.
    @State private var isExpanded: Bool

    init(queen: QueenRecord, today: Int, lineage: Lineage, onName: @escaping () -> Void) {
        self.queen = queen
        self.today = today
        self.lineage = lineage
        self.onName = onName
        _isExpanded = State(initialValue: queen.isReigning)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            record
        } label: {
            HStack {
                Image(systemName: "crown.fill")
                    .foregroundStyle(queen.isReigning ? Theme.queen : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(queen.title)
                        .font(.headline)
                    Text(parentage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if queen.isReigning {
                    Text("Reigning")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.queen)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityHint(isExpanded ? "Collapses her record" : "Expands her record")
        }
        .tint(Theme.queen)
        .sensoryFeedback(.selection, trigger: isExpanded)
    }

    /// Everything the game kept about her. Rows rather than a paragraph,
    /// because a record is looked at rather than read.
    private var record: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Reign", value: "\(queen.reignDays(on: today)) days")
            LabeledContent("Emerged", value: dayLabel(queen.emergedOnDay))
            LabeledContent("Mating", value: mating)
            LabeledContent("Quality at emergence", value: "\(Int((queen.quality * 100).rounded()))%")

            if !daughters.isEmpty {
                LabeledContent("Daughters") {
                    Text(daughters.map(\.title).spokenList)
                        .multilineTextAlignment(.trailing)
                }
            }

            if let ending = queen.ending {
                LabeledContent("How it ended", value: ending.displayName)
            }

            Button("Name Her", systemImage: "square.and.pencil", action: onName)
                .font(.subheadline)
                .padding(.top, 4)
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }

    private var parentage: String {
        guard let mother = queen.motherNumber,
              let record = lineage.queens.first(where: { $0.number == mother })
        else { return "Founding queen" }
        return "Daughter of \(record.title)"
    }

    /// Who was raised from her eggs and went on to reign.
    private var daughters: [QueenRecord] {
        lineage.queens.filter { $0.motherNumber == queen.number }
    }

    private var mating: String {
        guard let patrilines = queen.patrilines else { return "Never mated" }
        guard let day = queen.matedOnDay else { return "\(patrilines) drones" }
        return "\(patrilines) drones, \(dayLabel(day))"
    }

    /// Days are counted from the colony's founding, which past the first year
    /// is a number nobody can place.
    private func dayLabel(_ day: Int) -> String {
        "year \(day / Season.daysPerYear + 1), day \(day % Season.daysPerYear + 1)"
    }
}
