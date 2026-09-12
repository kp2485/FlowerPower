//
//  GlossaryView.swift
//  FlowerPower
//
//  The words the game uses, explained.
//
//  Ninety-odd terms, grouped by first letter and searchable, with the
//  cross-references tappable so one word leads to the next — which is how
//  anybody actually reads a glossary: in at "supersedure" and out twenty
//  minutes later somewhere near "patriline".
//
//  Every definition comes from `Glossary` in the package. The ones that name a
//  job, a posture, a pathogen, a predator, a queen cell, a cause of death, a
//  site or a resource come out of exhaustive switches over the engine's own
//  enums, so a word can never appear on one of the game's screens with nothing
//  behind it here.
//

import SwiftUI
import FlowerPowerCore

/// A term to push, by name.
///
/// Navigation is by value rather than by destination closure because the term
/// page links to other term pages: a `NavigationLink` whose destination is the
/// same view type it sits inside is an infinitely recursive type, and will not
/// compile. One `navigationDestination` registered here serves the whole
/// drill-down, however deep it goes.
private struct GlossaryRoute: Hashable {
    let term: String
}

struct GlossaryView: View {

    @State private var search = ""

    private var results: [GlossaryTerm] { Glossary.search(search) }

    var body: some View {
        List {
            if results.isEmpty {
                Section {
                    ContentUnavailableView.search(text: search)
                }
            } else {
                ForEach(Glossary.grouped(results)) { group in
                    Section(group.letter) {
                        ForEach(group.terms) { term in
                            NavigationLink(value: GlossaryRoute(term: term.term)) {
                                row(term)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Beekeeping terms")
        .navigationTitle("Glossary")
        .navigationDestination(for: GlossaryRoute.self) { route in
            GlossaryTermView(name: route.term)
        }
    }

    private func row(_ term: GlossaryTerm) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(term.term)
                .font(.body)
            Text(term.definition)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - One term

private struct GlossaryTermView: View {

    let name: String

    private var term: GlossaryTerm? { Glossary.term(named: name) }

    var body: some View {
        ScrollView {
            if let term {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(term.term)
                            .font(.title2.weight(.semibold))
                        Text(term.definition)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    let related = Glossary.relatedTerms(of: term)
                    if !related.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle("See also", systemImage: "arrow.triangle.branch")
                            ForEach(related) { other in
                                NavigationLink(value: GlossaryRoute(term: other.term)) {
                                    HStack {
                                        Text(other.term)
                                            .font(.subheadline.weight(.medium))
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }
                }
                .padding()
            } else {
                // Unreachable while `GlossaryTests` passes: every
                // cross-reference resolves to a real entry. Handled anyway,
                // because a missing word is not worth a crash.
                ContentUnavailableView(
                    "Not in the glossary",
                    systemImage: "character.book.closed",
                    description: Text("Nothing is filed under \(name).")
                )
                .padding(.top, 40)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(term?.term ?? name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        GlossaryView()
    }
}
