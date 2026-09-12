//
//  FloralTraitsView.swift
//  FlowerPower
//
//  Why the bees do what they do.
//
//  The science is the game's distinguishing feature and this is how the
//  player sees it: a corolla drawn to scale against a honey bee's reach, the
//  sugar in the nectar, the protein in the pollen and whether its amino acids
//  are complete. When foxglove yields nothing the page does not just say so,
//  it shows the tube.
//

import SwiftUI
import FlowerPowerCore

struct FloralTraitsView: View {

    let species: FlowerSpecies

    private var traits: FloralTraits { species.traits }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Why the bees work it the way they do", systemImage: "questionmark.circle")

            reach

            if traits.producesNectar {
                MeterView(
                    label: "Nectar sugar",
                    value: traits.nectarSugarConcentration / 0.6,
                    caption: "\(Int((traits.nectarSugarConcentration * 100).rounded()))% by weight",
                    tint: Theme.nectar,
                    symbolName: "drop.fill"
                )
                Text(sugarNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Produces no nectar at all. Pollen only.", systemImage: "drop.slash")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.caution)
            }

            MeterView(
                label: "Pollen protein",
                value: traits.pollenProteinFraction / 0.3,
                caption: "\(Int((traits.pollenProteinFraction * 100).rounded()))% crude protein",
                tint: Theme.pollen,
                symbolName: "circle.grid.3x3.fill"
            )

            if traits.pollenAminoAcidCompleteness < 0.8 {
                Label(
                    "Incomplete protein. Short of essential amino acids, so brood reared on this alone does badly however much is collected.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(Theme.caution)
                .fixedSize(horizontal: false, vertical: true)
            }

            Text(species.family.forageNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    // MARK: - The tube against the tongue

    private var reach: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Corolla depth")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(traits.producesNectar
                     ? String(format: "%.1f mm", traits.corollaDepthMillimetres)
                     : "open")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            CorollaDiagram(
                depth: traits.corollaDepthMillimetres,
                reach: BeeMorphology.nectarReachMillimetres,
                tolerance: BeeMorphology.reachToleranceMillimetres,
                accessible: traits.nectarAccessibility
            )
            .frame(height: 64)

            Text(reachNote)
                .font(.caption)
                .foregroundStyle(traits.isOutOfReach && traits.producesNectar ? Theme.caution : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reachNote: String {
        let reach = String(format: "%.1f", BeeMorphology.nectarReachMillimetres)
        guard traits.producesNectar else {
            return "There is no nectar to reach."
        }
        if traits.nectarAccessibility >= 1 {
            return "Well within a honey bee's reach of about \(reach) mm — \(String(format: "%.1f", BeeMorphology.proboscisLengthMillimetres)) mm of tongue plus the head she pushes in."
        }
        if traits.isOutOfReach {
            return "Far deeper than a honey bee can reach. A bumblebee flower: your bees can only rob it, and mostly do not."
        }
        return "Just past a honey bee's reach. She gets some when the flower is full and the nectar stands high in the tube, and little otherwise."
    }

    private var sugarNote: String {
        let concentration = traits.nectarSugarConcentration
        if concentration >= 0.45 {
            return "Thick nectar. Less water to drive off, so more honey for the same number of trips."
        }
        if concentration <= 0.28 {
            return "Thin nectar. The colony fans hard to ripen it, and a full load makes less honey than it looks."
        }
        return "Ordinary nectar, about a third sugar."
    }
}

/// A corolla drawn as a tube, with the bee's reach marked across it.
private struct CorollaDiagram: View {

    let depth: Double
    let reach: Double
    let tolerance: Double
    let accessible: Double

    /// The longest tube the diagram shows at full width; anything deeper is
    /// capped and labelled.
    private let scale: Double = 26

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let unit = width / scale
            let tubeWidth = min(width, max(8, depth * unit))
            let reachWidth = min(width, reach * unit)
            let toleranceWidth = min(width, (reach + tolerance) * unit)

            ZStack(alignment: .leading) {
                // The corolla.
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.wax.opacity(0.7))
                    .frame(width: tubeWidth, height: 36)
                    .overlay(alignment: .trailing) {
                        Circle()
                            .fill(Theme.nectar)
                            .frame(width: 10, height: 10)
                            .padding(.trailing, 4)
                    }

                // Where she can reach, and where she can just about reach.
                Rectangle()
                    .fill(Theme.healthy.opacity(0.25))
                    .frame(width: reachWidth, height: 36)
                Rectangle()
                    .fill(Theme.caution.opacity(0.18))
                    .frame(width: max(0, toleranceWidth - reachWidth), height: 36)
                    .offset(x: reachWidth)

                // The tongue.
                Capsule()
                    .fill(Theme.worker)
                    .frame(width: reachWidth, height: 4)
                    .offset(y: 24)
            }
            .overlay(alignment: .bottomLeading) {
                Text("reach \(String(format: "%.1f", reach)) mm")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .offset(y: 16)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The corolla against a honey bee's reach")
        .accessibilityValue("\(String(format: "%.1f", depth)) millimetres deep against a reach of \(String(format: "%.1f", reach)); \(Int(accessible * 100)) percent of the nectar is reachable")
    }
}
