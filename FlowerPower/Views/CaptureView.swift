//
//  CaptureView.swift
//  FlowerPower
//
//  The core loop, in one screen: point at a flower, take the picture, watch it
//  become forage.
//
//  The flow is deliberately forgiving. Identification runs after the shot is
//  already banked, so a slow classifier never blocks the player, and a flower it
//  cannot name still feeds the colony. Two things stop a capture: the image
//  plainly not being a flower at all, and a photograph from the library that
//  is already in the garden.
//

import SwiftUI
import PhotosUI
import FlowerPowerCore
import FlowerPowerGame

struct CaptureView: View {

    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The garden cell the player tapped on the map to get here, when they
    /// did. The flower goes there rather than wherever the engine would put it.
    var plantingAt: HexCoordinate? = nil

    @State private var pickerItem: PhotosPickerItem?
    @State private var stage: Stage = .choosing
    @State private var isUsingCamera = false

    /// Built asynchronously, because working out the best available
    /// identifier means asking the reference-print actor and the on-device
    /// model whether they are there.
    @State private var classifier: FlowerIdentifying?

    /// Photographs banked this session. The picker gives the shutter its own
    /// feedback; this is for the moment the flower becomes forage, which is
    /// the part the game cares about.
    @State private var recordings = 0

    /// A camera capture being worked on. Held so that closing the screen stops
    /// it: this is the one path with no `.task` to cancel for it, and a flower
    /// the player walked away from was still planted, for good, once the model
    /// finished. There is no way to remove a flower.
    @State private var capturing: Task<Void, Never>?

    enum Stage: Equatable {
        case choosing
        /// A library pick on its way down, which for a photograph in iCloud
        /// can be most of a minute.
        case loading
        case identifying(UIImage)
        case result(CaptureResult)
        case rejected(UIImage)
        case failed(String)
    }

    struct CaptureResult: Equatable {
        let image: UIImage
        let identification: FlowerIdentification
        let patchID: EntityID
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .choosing:
                    ChooserView(
                        pickerItem: $pickerItem,
                        onUseCamera: { isUsingCamera = true }
                    )
                case .loading:
                    ProgressView("Fetching the photograph…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .identifying(let image):
                    IdentifyingView(image: image)
                case .result(let result):
                    ResultView(
                        result: result,
                        onCorrect: { species, confidence in
                            store.attachIdentification(
                                species,
                                confidence: confidence,
                                to: result.patchID
                            )
                            // A person naming a flower has just labelled a
                            // photograph. That is exactly what the reference
                            // library is short of, so it is worth keeping —
                            // and it means identification gets better the more
                            // the game is played, which matters when nothing
                            // is bundled yet.
                            if let cgImage = result.image.cgImage {
                                Task.detached(priority: .utility) {
                                    await FeaturePrintStore.shared.learn(
                                        cgImage, as: species, source: .named
                                    )
                                }
                            }
                        },
                        onDone: { dismiss() }
                    )
                // The picker item is cleared on the way back, or choosing the
                // same photograph again is an equal item and `.task(id:)`
                // never runs — "Try again" did nothing.
                case .rejected(let image):
                    RejectedView(image: image) { pickerItem = nil; stage = .choosing }
                case .failed(let message):
                    FailureView(message: message) { pickerItem = nil; stage = .choosing }
                }
            }
            .navigationTitle("Find a Flower")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .sensoryFeedback(.success, trigger: recordings)
        .fullScreenCover(isPresented: $isUsingCamera) {
            CameraPicker(
                onCapture: { image in
                    isUsingCamera = false
                    capturing = Task { @MainActor in
                        let working = await Self.workingImage(from: image)
                        await handle(working, original: image, from: .camera)
                    }
                },
                onCancel: { isUsingCamera = false }
            )
            .ignoresSafeArea()
        }
        // `.task` hands back a @Sendable closure, which does not inherit the
        // view's main-actor isolation. Both bodies touch main-actor state.
        .task(id: pickerItem) { @MainActor in
            guard let pickerItem else { return }
            await handle(pickerItem)
        }
        .task { @MainActor in
            if classifier == nil {
                classifier = await FlowerClassifier.bundled()
            }
        }
        .onDisappear { capturing?.cancel() }
        // The screen swaps underneath a VoiceOver user with nothing to say so.
        .onChange(of: stage) { _, stage in
            switch stage {
            case .result(let result):
                AccessibilityNotification.Announcement(
                    "\(result.identification.species?.commonName ?? "A flower we cannot name"), added to your garden."
                ).post()
            case .rejected:
                AccessibilityNotification.Announcement("That does not look like a flower.").post()
            case .failed(let message):
                AccessibilityNotification.Announcement(message).post()
            default:
                break
            }
        }
    }

    // MARK: - Flow

    /// Where a photograph came from, which decides what is recorded for it.
    private enum Source {
        /// Just taken: nowhere yet, so it is saved to the library first.
        case camera
        /// Chosen from the library: already there, and already knowing when it
        /// was taken. `nil` if the picker did not say which photograph it was,
        /// which with the shared library it should.
        case library(String?)
    }

    @MainActor
    private func handle(_ item: PhotosPickerItem) async {
        // Before anything slower: a photograph already in the garden is not a
        // second patch. Every pick used to be saved as a new copy, so the same
        // photo chosen twice was two patches; now that the original is used,
        // the second pick can be recognised — and it is, before the model
        // spends ten seconds identifying it.
        if let identifier = item.itemIdentifier,
           store.snapshot.patches.contains(where: {
               $0.photoLocalIdentifier == identifier
                   || $0.photoLocalIdentifier == PhotoLibrary.copy(of: identifier)
           }) {
            stage = .failed("That photograph is already in your garden.")
            return
        }

        // Asked now, straight after the pick it is for, rather than at the
        // end of identifying — which on the simulator put the prompt over a
        // spinner half a minute after the photograph was chosen, as if out of
        // nowhere. `libraryPhoto` still asks if this was somehow skipped.
        if PhotoLibrary.authorisationStatus == .notDetermined {
            await PhotoLibrary.requestAccess()
        }

        stage = .loading
        do {
            // Decoded at working size, upright, and off the main actor. A
            // 48-megapixel original or a panorama decoded whole is hundreds
            // of megabytes, and it was then held, shown and handed to Vision
            // three times over.
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = await Self.workingImage(from: data)
            else {
                stage = .failed("That image could not be read.")
                return
            }
            await handle(image, original: nil, from: .library(item.itemIdentifier))
        } catch {
            // Picking another photograph, or closing, cancels this one. The
            // new one owns the screen now and this must not write over it.
            guard !Task.isCancelled else { return }
            stage = .failed(error.localizedDescription)
        }
    }

    /// Everything after "we have an image", shared by the camera and the
    /// library picker. The two differ only in where the pixels came from —
    /// and so in whether anything has to be written to the library at all.
    ///
    /// `image` is the working copy — upright and at most
    /// `PhotoLibrary.workingPixelSize` on its long edge — and is what is
    /// identified, shown and learned from. `original` is the full camera
    /// capture, which is what goes into the photo library.
    @MainActor
    private func handle(_ image: UIImage, original: UIImage?, from source: Source) async {
        do {
            stage = .identifying(image)

            guard let cgImage = image.cgImage else {
                stage = .failed("That image could not be read.")
                return
            }

            // If the capture screen was opened and used faster than the
            // classifier could be built, wait for it rather than identify
            // with nothing: a bare classifier has no rungs at all, and
            // would call every flower unnameable.
            let identifier: FlowerIdentifying
            if let classifier {
                identifier = classifier
            } else {
                let built = await FlowerClassifier.bundled()
                classifier = built
                identifier = built
            }
            let identification = try await Self.identify(
                cgImage,
                orientation: image.imageOrientation.cgOrientation,
                with: identifier
            )

            // The last moment before anything is written. Identifying takes
            // seconds and ignores cancellation, so this is where closing the
            // screen is honoured.
            guard !Task.isCancelled else { return }

            guard identification.looksLikeAFlower else {
                stage = .rejected(image)
                return
            }

            let saved: PhotoLibrary.PhotoMetadata
            switch source {
            case .camera:
                // Nothing holds this photograph yet, so bank it.
                saved = try await PhotoLibrary.save(original ?? image)
            case .library(let identifier):
                saved = try await libraryPhoto(image, identifier: identifier)
            }

            let patchID = store.recordPhotograph(
                localIdentifier: saved.localIdentifier,
                species: identification.species,
                confidence: identification.confidence,
                takenAt: saved.takenAt,
                at: plantingAt
            )

            recordings += 1

            stage = .result(CaptureResult(
                image: image,
                identification: identification,
                patchID: patchID
            ))

        } catch {
            guard !Task.isCancelled else { return }
            stage = .failed(error.localizedDescription)
        }
    }

    // MARK: - Off the main actor

    /// Identification, off the main actor.
    ///
    /// With approachable concurrency a nonisolated `async` function runs on
    /// its caller's actor, so `identify` called from here ran BioCLIP — a
    /// synchronous Vision request on a ViT-L, then a scan of 57,000 names —
    /// on the main thread, and the spinner and the Close button froze.
    @concurrent
    nonisolated private static func identify(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation,
        with identifier: FlowerIdentifying
    ) async throws -> FlowerIdentification {
        try await identifier.identify(image, orientation: orientation)
    }

    @concurrent
    nonisolated private static func workingImage(from data: Data) async -> UIImage? {
        PhotoLibrary.workingImage(from: data)
    }

    @concurrent
    nonisolated private static func workingImage(from image: UIImage) async -> UIImage {
        PhotoLibrary.workingImage(from: image)
    }

    /// A photograph chosen from the library, as it already is: its own date,
    /// and no second copy of it in the camera roll.
    ///
    /// Every pick used to be saved as a fresh photo stamped with the current
    /// time, which left a duplicate in the library each time and dated a
    /// flower photographed last summer to this afternoon. Using the original
    /// costs nothing and is simply truer: the patch was found when the picture
    /// was taken, not when it was picked out of a grid.
    @MainActor
    private func libraryPhoto(
        _ image: UIImage,
        identifier: String?
    ) async throws -> PhotoLibrary.PhotoMetadata {
        // Reading the original's date needs read access, which nothing asked
        // for until now: the picker itself needs none, and the camera path
        // only ever wrote.
        if PhotoLibrary.authorisationStatus == .notDetermined {
            await PhotoLibrary.requestAccess()
        }

        if let identifier, let original = PhotoLibrary.metadata(for: identifier) {
            return original
        }

        // The original cannot be read — most often because the player gave
        // limited access, and a photo chosen in the picker is not one of the
        // photos they shared. A copy is then the only way to show it in the
        // garden, and it is dated today rather than whenever the original was
        // taken, because a copy is all there is to read a date from. Kept in
        // the app, not written back to the library the photo came from: that
        // raised a second permission prompt and left a duplicate.
        let copy = try PhotoLibrary.keepInApp(image)
        // Remembered, because the copy has an identifier of its own: without
        // this the picker's never matched again, and every further pick of
        // the same photograph was another flower and another copy.
        if let identifier { PhotoLibrary.remember(copy: copy.localIdentifier, of: identifier) }
        return copy
    }
}

// MARK: - Stages

private struct ChooserView: View {

    @Binding var pickerItem: PhotosPickerItem?
    var onUseCamera: () -> Void

    /// All on one screen while it fits. At the largest text sizes it does not,
    /// and the buttons were pushed off the bottom with no way to reach them.
    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
    }

    private var content: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "camera.macro")
                .font(.system(size: 64))
                .foregroundStyle(Theme.honey)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("What have you found?")
                    .font(.title2.weight(.semibold))
                Text("Photograph a flower and your bees will work it. Closer and clearer is better — a flower we can name is worth more.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                if CameraPicker.isAvailable {
                    Button(action: onUseCamera) {
                        Label("Take a Photo", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.honey)
                    .foregroundStyle(Theme.onHoney)
                    .controlSize(.large)

                    // Secondary once there is a camera above it: the point of
                    // the game is going outside and finding something.
                    photoLibraryButton
                        .buttonStyle(.bordered)
                        .tint(Theme.honey)
                        .controlSize(.large)
                } else {
                    // No camera, which means the simulator or a device with
                    // the camera restricted. The library is the only way in.
                    photoLibraryButton
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.honey)
                        .foregroundStyle(Theme.onHoney)
                        .controlSize(.large)
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var photoLibraryButton: some View {
        PhotosPicker(
            selection: $pickerItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            Label("Choose a Photo", systemImage: "photo.on.rectangle")
                .frame(maxWidth: .infinity)
        }
    }
}

private struct IdentifyingView: View {

    let image: UIImage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweeping = false
    /// Set once the wait has run long. Placing a plant among 57,000 names
    /// took about thirty seconds on the simulator, where the model runs on
    /// the processor, and a spinner alone for that long reads as a hang.
    @State private var isSlow = false

    var body: some View {
        VStack(spacing: 20) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 300)
                // A band of honey light passing over the photograph, so the
                // wait reads as something looking rather than as a hang.
                .overlay {
                    if !reduceMotion {
                        GeometryReader { geometry in
                            LinearGradient(
                                colors: [.clear, Theme.honey.opacity(0.45), .clear],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: geometry.size.height * 0.35)
                            .offset(y: sweeping ? geometry.size.height : -geometry.size.height * 0.35)
                            .blendMode(.plusLighter)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("The photograph you took")

            ProgressView("Looking at it…")
                .tint(Theme.honey)

            if isSlow {
                Text("Every flowering plant there is gets a look, so this can take a little while.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .padding()
        .task {
            try? await Task.sleep(for: .seconds(6))
            withAnimation { isSlow = true }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                sweeping = true
            }
        }
    }
}

/// "A keystone find!" — said with a little ceremony, because these are the
/// flowers that carry a colony through the gaps and the game should make
/// finding one feel like it.
private struct SpecialFindBanner: View {

    let species: FlowerSpecies
    let revealed: Bool

    private var title: String {
        species.isKeystone ? "A keystone find!" : "A rare find!"
    }

    private var detail: String {
        species.isKeystone
            ? "This blooms when little else does. Your bees will lean on it."
            : "Uncommon forage, and worth more to the colony for it."
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: species.isKeystone ? "star.circle.fill" : "sparkles")
                .font(.title)
                .foregroundStyle(Theme.queen)
                .symbolEffect(.bounce, value: revealed)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(Theme.queen.opacity(0.12), in: .rect(cornerRadius: 14))
        .scaleEffect(revealed ? 1 : 0.85)
        .opacity(revealed ? 1 : 0)
        .accessibilityElement(children: .combine)
    }
}

private struct ResultView: View {

    let result: CaptureView.CaptureResult
    var onCorrect: (FlowerSpecies, Double) -> Void
    var onDone: () -> Void

    /// Only to find out where the flower was planted: the engine chooses the
    /// cell, and this screen is the one place the player finds out which.
    @Environment(GameStore.self) private var store

    @State private var isNaming = false
    /// What the player has settled on, so the card reflects a correction
    /// immediately rather than waiting for the next snapshot.
    @State private var corrected: FlowerSpecies?

    /// Flipped once the card is on screen, for the entrance and, for a find
    /// worth celebrating, the burst and the tap that go with it.
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A keystone or a rare plant: the finds that matter most to a colony,
    /// and the ones worth making a fuss of.
    private var isSpecialFind: Bool {
        guard corrected == nil, let species = result.identification.species else { return false }
        return species.isKeystone || species.rarity == .rare
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(uiImage: result.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("The photograph you took")

                // Where it went. The flower is already banked by the time this
                // screen appears, and it is banked *somewhere* now — a cell of
                // the garden at a real distance, which is the number the
                // foraging economics are priced in.
                if let metres = plantedMetres {
                    Text("Planted in your garden, \(metres) m from the nest.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Planted in your garden, \(metres) metres from the nest.")
                }

                if isSpecialFind, let species = result.identification.species {
                    SpecialFindBanner(species: species, revealed: revealed)
                }

                if let species = corrected ?? result.identification.species {
                    if corrected == nil, let rank = result.identification.rank, rank < .species {
                        // Says plainly how far the placement got. A family is a
                        // real answer, not a failure, and the player should be
                        // told which they have rather than left to assume a
                        // species was meant.
                        RankNote(rank: rank, taxon: result.identification.taxon)
                    }

                    IdentifiedCard(
                        species: species,
                        confidence: corrected == nil
                            ? result.identification.confidence
                            : SpeciesPickerView.manualConfidence,
                        alternatives: corrected == nil
                            ? result.identification.alternatives
                            : [],
                        namedByPlayer: corrected != nil,
                        onPick: correct,
                        onNameItYourself: { isNaming = true }
                    )
                } else {
                    UnidentifiedCard(onNameItYourself: { isNaming = true })
                }

                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.honey)
                    .foregroundStyle(Theme.onHoney)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .sheet(isPresented: $isNaming) {
            SpeciesPickerView { species in
                correct(to: species, confidence: SpeciesPickerView.manualConfidence)
            }
        }
        .sensoryFeedback(.levelChange, trigger: revealed) { _, now in now && isSpecialFind }
        .onAppear {
            if reduceMotion {
                revealed = true
            } else {
                withAnimation(.spring(duration: 0.5, bounce: 0.35).delay(0.15)) { revealed = true }
            }
        }
    }

    private func correct(to species: FlowerSpecies, confidence: Double) {
        corrected = species
        onCorrect(species, confidence)
    }

    /// How far the bees will fly to this one, or nil for a patch with no cell
    /// — a colony whose save has no terrain, where the line would be a claim
    /// about a garden that does not exist.
    private var plantedMetres: Int? {
        let snapshot = store.snapshot
        guard let patch = snapshot.patches.first(where: { $0.id == result.patchID }),
              let cell = patch.cell
        else { return nil }

        // Through the garden, which is the authority on what a cell is worth;
        // the cell's own distance from the origin is the same number, and is
        // the fallback rather than the first answer for that reason.
        let metres = snapshot.terrain?.garden.first { $0.cell == cell }?.distanceMetres
            ?? cell.metresFromOrigin
        return Int(metres)
    }
}

/// Explains a placement that stopped short of a species.
private struct RankNote: View {

    let rank: TaxonomicRank
    let taxon: Taxon?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(headline, systemImage: "leaf.arrow.triangle.circlepath")
                .font(.subheadline.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var headline: String {
        switch rank {
        case .family: return "Placed to a family"
        case .genus: return "Placed to a genus"
        case .species: return "Placed to a species"
        }
    }

    private var detail: String {
        let name = taxon?.scientificName ?? "this group"
        switch rank {
        case .family:
            return "This is \(name), but not which member of it. Your bees do not "
                + "mind: the family decides the shape of the flower, and that is "
                + "what settles whether they can reach the nectar."
        case .genus:
            return "This is \(name), but not which species. Close relatives offer "
                + "much the same forage, so your bees will work it as one of them."
        case .species:
            return name
        }
    }
}

private struct IdentifiedCard: View {

    let species: FlowerSpecies
    let confidence: Double
    let alternatives: [FlowerIdentification.Alternative]
    /// A name the player picked. It carries a confidence for the economy's
    /// sake (see `SpeciesPickerView.manualConfidence`), but "Confidence 80%"
    /// under a name they had just chosen read as the game doubting them.
    var namedByPlayer = false
    var onPick: (FlowerSpecies, Double) -> Void
    var onNameItYourself: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// How sure, in words. A bare "100%" beside a placement the model could
    /// still have wrong promised more than any identifier can give.
    private var sureness: String {
        switch confidence {
        case 0.9...: return "Very sure"
        case 0.6..<0.9: return "Fairly sure"
        case 0.4..<0.6: return "Unsure"
        default: return "A guess"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(species.commonName)
                        .font(.title3.weight(.semibold))
                    if let scientific = species.scientificName {
                        Text(scientific)
                            .font(.caption.italic())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if species.rarity != .common {
                    Label(species.rarity.displayName, systemImage: "star.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.queen)
                }
            }

            if namedByPlayer {
                Label("Named by you", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                MeterView(
                    label: "Confidence",
                    value: confidence,
                    caption: sureness,
                    tint: confidence > 0.6 ? Theme.healthy : Theme.caution
                )
                .accessibilityValue("\(sureness), \(Int((confidence * 100).rounded())) percent")
            }

            if species.isKeystone {
                Label(
                    "This one flowers when your bees have few other options. A real find.",
                    systemImage: "star.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(Theme.honey)
                .fixedSize(horizontal: false, vertical: true)
            }

            // Offered as buttons rather than prose. The runners-up were
            // already being computed and shown, but only as a sentence, so a
            // player who could see the answer was wrong had no way to say so.
            if !alternatives.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Might also be")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    // Two or three flower names side by side stop fitting
                    // somewhere around the first accessibility size, and a
                    // runner-up the player cannot read is no use to them.
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 6) { alternativeButtons }
                    } else {
                        HStack(spacing: 8) { alternativeButtons }
                    }
                }
            }

            Button("Something else", action: onNameItYourself)
                .font(.caption)
                .tint(Theme.honey)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private var alternativeButtons: some View {
        ForEach(alternatives, id: \.species.id) { alternative in
            Button {
                onPick(alternative.species, alternative.confidence)
            } label: {
                Text(alternative.species.commonName)
                    .frame(minHeight: 32)
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
    }
}

private struct UnidentifiedCard: View {

    var onNameItYourself: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("A flower, but we cannot name it", systemImage: "questionmark.circle")
                .font(.headline)
            Text("Your bees will work it anyway, at a reduced yield. A closer, sharper photo in better light usually does it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Name It Yourself", action: onNameItYourself)
                .buttonStyle(.bordered)
                .tint(Theme.honey)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct RejectedView: View {

    let image: UIImage
    var onRetry: () -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
    }

    private var content: some View {
        VStack(spacing: 20) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.caution, lineWidth: 2))
                .accessibilityLabel("The photograph you took")

            ContentUnavailableView {
                Label("No Flower Found", systemImage: "eye.slash")
            } description: {
                Text("There does not seem to be a flower or plant in this picture. Your bees are particular.")
            } actions: {
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.honey)
                    .foregroundStyle(Theme.onHoney)
            }
        }
        .padding()
    }
}

private struct FailureView: View {

    let message: String
    var onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Something Went Wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(Theme.honey)
                .foregroundStyle(Theme.onHoney)
        }
    }
}

// MARK: - Orientation bridging

extension UIImage.Orientation {
    var cgOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

#Preview {
    CaptureView()
        .environment(GameStore.preview())
}
