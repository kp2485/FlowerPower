//
//  CaptureView.swift
//  FlowerPower
//
//  The core loop, in one screen: point at a flower, take the picture, watch it
//  become forage.
//
//  The flow is deliberately forgiving. Identification runs after the shot is
//  already banked, so a slow classifier never blocks the player, and a flower it
//  cannot name still feeds the colony. The only thing that stops a capture is
//  the image plainly not being a flower at all.
//

import SwiftUI
import PhotosUI
import CoreLocation
import FlowerPowerCore
import FlowerPowerGame

struct CaptureView: View {

    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var stage: Stage = .choosing
    @State private var locationProvider = LocationProvider()
    @State private var isUsingCamera = false

    private let classifier = FlowerClassifier.bundled()

    enum Stage: Equatable {
        case choosing
        case identifying(UIImage)
        case result(CaptureResult)
        case rejected(UIImage)
        case failed(String)
    }

    struct CaptureResult: Equatable {
        let image: UIImage
        let identification: FlowerIdentification
        let patchID: EntityID
        let hasLocation: Bool
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
                                    FeaturePrintStore.shared.learn(
                                        cgImage, as: species, source: .named
                                    )
                                }
                            }
                        },
                        onDone: { dismiss() }
                    )
                case .rejected(let image):
                    RejectedView(image: image) { stage = .choosing }
                case .failed(let message):
                    FailureView(message: message) { stage = .choosing }
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
        .fullScreenCover(isPresented: $isUsingCamera) {
            CameraPicker(
                onCapture: { image in
                    isUsingCamera = false
                    Task { @MainActor in await handle(image) }
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
            locationProvider.requestWhenInUse()
        }
    }

    // MARK: - Flow

    @MainActor
    private func handle(_ item: PhotosPickerItem) async {
        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                stage = .failed("That image could not be read.")
                return
            }
            await handle(image)
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    /// Everything after "we have an image", shared by the camera and the
    /// library picker. The two differ only in where the pixels came from —
    /// and in whether the photo already knows where it was taken.
    @MainActor
    private func handle(_ image: UIImage) async {
        do {
            stage = .identifying(image)

            guard let cgImage = image.cgImage else {
                stage = .failed("That image could not be read.")
                return
            }

            let identification = try await classifier.identify(
                cgImage,
                orientation: image.imageOrientation.cgOrientation
            )

            guard identification.looksLikeAFlower else {
                stage = .rejected(image)
                return
            }

            // Bank the photo — including its location, if the player has
            // granted it and we have a recent fix.
            let location = locationProvider.currentLocation
            let saved = try await PhotoLibrary.save(image, location: location)

            let patchID = store.recordPhotograph(
                localIdentifier: saved.localIdentifier,
                species: identification.species,
                confidence: identification.confidence,
                coordinate: saved.coordinate,
                takenAt: saved.takenAt
            )

            stage = .result(CaptureResult(
                image: image,
                identification: identification,
                patchID: patchID,
                hasLocation: saved.coordinate != nil
            ))

        } catch {
            stage = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Stages

private struct ChooserView: View {

    @Binding var pickerItem: PhotosPickerItem?
    var onUseCamera: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "camera.macro")
                .font(.system(size: 64))
                .foregroundStyle(Theme.honey)

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

    var body: some View {
        VStack(spacing: 20) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            ProgressView("Looking at it…")
                .tint(Theme.honey)
        }
        .padding()
    }
}

private struct ResultView: View {

    let result: CaptureView.CaptureResult
    var onCorrect: (FlowerSpecies, Double) -> Void
    var onDone: () -> Void

    @State private var isNaming = false
    /// What the player has settled on, so the card reflects a correction
    /// immediately rather than waiting for the next snapshot.
    @State private var corrected: FlowerSpecies?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(uiImage: result.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                if let species = corrected ?? result.identification.species {
                    IdentifiedCard(
                        species: species,
                        confidence: corrected == nil
                            ? result.identification.confidence
                            : SpeciesPickerView.manualConfidence,
                        alternatives: corrected == nil
                            ? result.identification.alternatives
                            : [],
                        onPick: correct,
                        onNameItYourself: { isNaming = true }
                    )
                } else {
                    UnidentifiedCard(onNameItYourself: { isNaming = true })
                }

                if !result.hasLocation {
                    Label(
                        "No location on this photo, so it will not appear on the map. Your bees still work it, at a guessed distance.",
                        systemImage: "location.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.honey)
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
    }

    private func correct(to species: FlowerSpecies, confidence: Double) {
        corrected = species
        onCorrect(species, confidence)
    }
}

private struct IdentifiedCard: View {

    let species: FlowerSpecies
    let confidence: Double
    let alternatives: [FlowerIdentification.Alternative]
    var onPick: (FlowerSpecies, Double) -> Void
    var onNameItYourself: () -> Void

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

            MeterView(
                label: "Confidence",
                value: confidence,
                caption: String(format: "%.0f%%", confidence * 100),
                tint: confidence > 0.6 ? Theme.healthy : Theme.caution
            )

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
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 8) {
                        ForEach(alternatives, id: \.species.id) { alternative in
                            Button(alternative.species.commonName) {
                                onPick(alternative.species, alternative.confidence)
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Button("Something else", action: onNameItYourself)
                .font(.caption)
                .tint(Theme.honey)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
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
        VStack(spacing: 20) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.caution, lineWidth: 2))

            ContentUnavailableView {
                Label("No Flower Found", systemImage: "eye.slash")
            } description: {
                Text("There does not seem to be a flower or plant in this picture. Your bees are particular.")
            } actions: {
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.honey)
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
        }
    }
}

// MARK: - Location

/// Supplies a coarse location for freshly captured photos.
///
/// Deliberately undemanding: when-in-use only, reduced accuracy, and the whole
/// game works without it. Location turns photographs into map pins and real
/// foraging distances, which is a nice thing to have and not a thing to insist on.
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private(set) var currentLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestWhenInUse() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways else { return }
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // No location simply means no map pin.
        currentLocation = nil
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
