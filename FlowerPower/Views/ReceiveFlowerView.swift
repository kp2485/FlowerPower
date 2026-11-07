//
//  ReceiveFlowerView.swift
//  FlowerPower
//
//  A flower somebody sent, before it becomes part of the garden.
//
//  There is a screen here rather than a silent import for two reasons. The
//  player should see who it is from and what they said, because that is the
//  whole of the feature — a gift that lands invisibly is not a gift. And
//  content arriving from outside the app should be shown to a person before
//  it is acted on, not merged into their game because a link was tapped.
//

import SwiftUI
import FlowerPowerCore
import FlowerPowerGame

struct ReceiveFlowerView: View {

    let share: FlowerShare

    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var outcome: GameStore.ImportOutcome?
    /// A flower entering the garden is the same event as photographing one,
    /// and worth the same tap. Counted, so nothing fires on appearance.
    @State private var imports = 0

    /// Decoded once, off the main actor and through the guarded decoder: what
    /// arrives is somebody else's file, and a share's size limit is on its
    /// compressed bytes rather than the pixels they unpack to.
    @State private var image: UIImage?
    @State private var hasDecoded = false

    private var alreadyHave: Bool { store.hasImported(share) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    photograph

                    VStack(spacing: 6) {
                        Text(share.displayName)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)

                        if let species = share.species, let scientific = species.scientificName {
                            Text(scientific)
                                .font(.caption.italic())
                                .foregroundStyle(.secondary)
                        }

                        if let sender = share.sharedBy {
                            Text("Sent by \(sender)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let note = share.note {
                        // Text written by another person. `FlowerShare`
                        // stripped the newlines and capped the length before
                        // it ever reached here.
                        Text("\u{201C}\(note)\u{201D}")
                            .font(.callout)
                            .italic()
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }

                    detail

                    action
                }
                .padding()
            }
            .navigationTitle("A Flower For You")
            .navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.success, trigger: imports)
            .task { @MainActor in
                image = await Self.decoded(share.imageData)
                hasDecoded = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(outcome == nil ? "Not Now" : "Done") { dismiss() }
                }
            }
        }
    }

    @concurrent
    nonisolated private static func decoded(_ data: Data) async -> UIImage? {
        PhotoLibrary.workingImage(from: data)
    }

    @ViewBuilder
    private var photograph: some View {
        if !hasDecoded {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
        } else if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("The photograph of \(share.displayName) you were sent")
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(.quaternary)
                .frame(height: 200)
                .overlay {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement()
                .accessibilityLabel("The photograph could not be shown")
        }
    }

    /// When the flower is named, the one thing worth saying about it is when
    /// it flowers, since that is what decides whether it helps. An unnamed one
    /// shows nothing rather than an empty card: the bees work it either way,
    /// and there is nothing to promise about it in advance.
    @ViewBuilder
    private var detail: some View {
        if let species = share.species {
            Label(
                Season.allCases
                    .filter(species.bloomSeasons.contains)
                    .map { $0.rawValue.capitalized }
                    .joined(separator: ", ")
                    + (species.isKeystone
                       ? " — and one of the plants that carries a colony through the gaps"
                       : ""),
                systemImage: "calendar"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    @ViewBuilder
    private var action: some View {
        switch outcome {
        case .added:
            Label("Added to your garden", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Theme.healthy)

        case .alreadyHave:
            Label("You already have this one", systemImage: "checkmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case nil:
            if alreadyHave {
                Label("You already have this one", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    accept()
                } label: {
                    Label("Give It to My Bees", systemImage: "hexagon.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.honey)
                .foregroundStyle(Theme.onHoney)
                .controlSize(.large)
            }
        }
    }

    private func accept() {
        // The picture is kept first. If it were stored after the patch, a
        // failure here would leave a flower in the garden with nothing to
        // show for it.
        // Re-encoded rather than filed as it came, so what stays is an ordinary
        // JPEG of a sensible size whatever the file claimed to be.
        if let image, let data = SharedImageStore.prepareForSharing(image) {
            SharedImageStore.store(data, forShare: share.id)
        }
        let result = store.importShared(share)
        outcome = result
        if case .added = result { imports += 1 }

        // A flower arriving with a name attached is a labelled photograph,
        // which is what the reference library is built from. Somebody else's
        // identification is worth rather less than one this player made
        // themselves, but it is a real example of a real flower and the
        // library records where its labels came from.
        if let species = share.species, let cgImage = image?.cgImage {
            Task.detached(priority: .utility) {
                await FeaturePrintStore.shared.learn(cgImage, as: species, source: .received)
            }
        }
    }
}
