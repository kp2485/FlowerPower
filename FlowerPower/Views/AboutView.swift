//
//  AboutView.swift
//  FlowerPower
//
//  What the thing actually is.
//
//  An about page in an idle game is usually a version number and a credit.
//  This one says what the simulation models and how the difficulty was
//  arrived at, because both are load-bearing for how the game should be read:
//  a colony that dies here has not cheated the player, it has done what most
//  wild colonies do, and the only honest way to say so is to say what the
//  number is and how it was measured.
//
//  Every figure below comes from PLAN.md, and every one of them is from the
//  same command on a deterministic release build — 200 colonies over two
//  simulated years. They are quoted rather than computed because nothing in
//  the app can measure them; if the balance moves, this file moves with it.
//

import SwiftUI

struct AboutView: View {

    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: Self.version)
                LabeledContent("Build", value: Self.build)
            } header: {
                Text("FlowerPower")
            }

            Section {
                Text("A wild colony of honey bees, simulated properly. Foragers age into their jobs, brood takes the days it really takes to develop, wax is drawn only out of a nectar flow, the cluster burns honey to hold its temperature through winter, varroa breeds in capped brood, and a crowded nest raises swarm cells and divides. Nectar and pollen come from the floral traits of the plants you photograph — corolla depth against a honey bee's reach, sugar concentration apart from volume, pollen protein apart from abundance.")
            } header: {
                Text("What it models")
            }

            Section {
                Text("The difficulty is measured, not guessed. Across 200 simulated colonies run for two years each, 89% see their first spring and 66% their second on the standard setting. That is close to what happens to real unmanaged swarms, and it means losing a colony is the ordinary arc of the thing rather than a punishment.")
                Text("Five modelling errors were found by tracing single colonies through their deaths rather than by reading the average — comb being drawn out of the winter larder, a second swarm cast on the day a new queen mated, and three queen bugs before those. Each of them made the game easier or harder for a reason that had nothing to do with design.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("How it is balanced")
            } footer: {
                Text("Every balance figure in the game comes from a deterministic release build and reproduces byte for byte.")
            }

            Section {
                Text("Worker job ages, brood development times, nest sites and the list of things that raid a hive are taken from the beekeeping and entomology notes the project started from, kept in the repository as docs/RESEARCH.md and enforced by the engine's own tests.")
                Text("Where the notes and the engine disagree the disagreement is deliberate and written down. Larval periods are the real six, seven and five days rather than a flat nine; swarming is tied to congestion and queen pheromone rather than to how much honey is in the nest, because congestion is the thing the honey was standing in for.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Where the science comes from")
            }

            Section {
                Text("Your photographs stay on your device and in your own photo library. Flowers and swarms travel between players as files through the share sheet — there is no server and no account. A shared flower carries a coordinate only if you choose to include one, and rounds it to about a kilometre by default, because a flower photograph's location is where a person was standing.")
            } header: {
                Text("Your photographs")
            }
        }
        .navigationTitle("About FlowerPower")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Version

    /// Read from the bundle rather than kept in a constant here, so it cannot
    /// drift from what was actually shipped.
    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "—"
    }

    private static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "—"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AboutView()
    }
}
