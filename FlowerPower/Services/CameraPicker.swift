//
//  CameraPicker.swift
//  FlowerPower
//
//  Taking the photograph without leaving the app — and taking it close.
//
//  This was `UIImagePickerController`, chosen because it brought its own
//  shutter, focus, flash and permission handling, and the camera is not where
//  this app's interest lies. Three things about the stock picker turned out to
//  matter more than the lines it saved. It opens the wide camera and stays on
//  it, so a flower a few centimetres away — which is how a flower has to be
//  photographed for a classifier that sees 224 pixels of it — went soft at the
//  wide lens's minimum focus distance, where Camera.app would have swapped to
//  the ultra-wide's macro mode. It gives no say over focus or exposure, so a
//  pale flower against dark leaves came out blown. And it hands back a
//  `UIImage` already decoded, so the only way into the photo library was to
//  encode it again: a second lossy pass over the one image the whole game is
//  built on.
//
//  So this is an `AVCaptureSession` of our own, kept as small as it can be.
//  The back *virtual* camera, so iOS swaps lenses for a close subject the way
//  Camera.app does. Continuous focus and exposure, with a tap to place them.
//  A square guide, because the classifiers centre-crop to a square and a
//  flower outside it is not seen. And the camera's own HEIF bytes, which go to
//  Photos untouched while the decoded image goes on to be identified.
//
//  The static surface — `isAvailable`, `authorisationStatus`, `requestAccess`
//  — is what the picker had, so `CaptureView` asks the same questions. What
//  comes back is a `CameraCapture` rather than an image. A photograph taken
//  this way exists nowhere until something writes it down, so
//  `PhotoLibrary.save(_:)` banks it in the player's library and hands back the
//  identifier the garden then shows it by. That is the one difference from a
//  photograph chosen out of the library, which is already there and is used
//  where it lies.
//
//  Everything that touches the session runs on one serial queue, through an
//  actor whose executor is that queue: `startRunning` blocks for a good
//  fraction of a second, and AVFoundation wants its configuration done off
//  the main thread. The view talks to the actor and never to the session.
//

import SwiftUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers

// MARK: - What a capture is

/// A photograph straight out of the camera, in both the forms it is needed.
struct CameraCapture: Sendable {
    /// Decoded for showing and identifying. Its orientation metadata is set
    /// so it draws upright; `PhotoLibrary.workingImage(from:)` redraws it to
    /// `.up` pixels at working size, as it did the picker's image.
    let image: UIImage
    /// The camera's own encoding of the same photograph — HEIF where the
    /// device can make one, JPEG otherwise. This is what goes to Photos, so
    /// nothing re-encodes the picture on the way.
    let data: Data
    let type: UTType
}

// MARK: - The screen

struct CameraPicker: View {

    let onCapture: (CameraCapture) -> Void
    let onCancel: () -> Void

    /// Whether this device can actually take a picture. False in the
    /// simulator, which is where most of this will first be run, and
    /// `CaptureView` then offers the library alone.
    static var isAvailable: Bool {
        CameraSession.backCamera() != nil
    }

    static var authorisationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    @discardableResult
    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    @State private var model = CameraModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.phase {
            case .denied(let restricted):
                DeniedView(restricted: restricted, onCancel: onCancel)
            case .starting, .running:
                viewfinder
            }
        }
        // Controls over a viewfinder are white on black whatever the system
        // appearance, and `Theme.honey` reads as the bright gold on it.
        // Scoped to this view: `preferredColorScheme` is a preference that
        // travels up to the presentation and stayed dark on the capture
        // sheet after the camera was dismissed.
        .environment(\.colorScheme, .dark)
        .task { await model.start() }
        .onDisappear { model.stop() }
        // Nothing worse than this, and then the library button is still
        // there: `CaptureView` falls back to it exactly as when there is no
        // camera at all.
        .alert(
            "The camera could not be started",
            isPresented: Binding(
                get: { model.failure != nil },
                set: { if !$0 { model.failure = nil } }
            )
        ) {
            Button("OK", action: onCancel)
        } message: {
            Text(model.failure ?? "")
        }
    }

    private var viewfinder: some View {
        ZStack {
            CameraPreview(
                session: model.captureSession,
                isRunning: model.phase == .running,
                onTap: { layerPoint, devicePoint in
                    model.focus(at: devicePoint, shownAt: layerPoint)
                }
            )
            .overlay {
                if let point = model.focusPoint {
                    FocusRing()
                        .position(point)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.focusPoint)
            .ignoresSafeArea()
            // A live picture is nothing to a screen reader; the guide's hint
            // and the controls are the screen.
            .accessibilityHidden(true)

            if model.phase == .starting {
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel("Starting the camera")
            }

            // The shutter's blink. Not under Reduce Motion: the shutter dims
            // while the capture is in flight, which says the same thing.
            if !reduceMotion {
                Color.black
                    .opacity(model.shutterBlink ? 1 : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.15), value: model.shutterBlink)
            }

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 16)
                guide
                Spacer(minLength: 16)
                shutter
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private var topBar: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(.black.opacity(0.35), in: Capsule())
                .accessibilityLabel("Cancel")

            Spacer()

            if model.hasFlash {
                Button {
                    model.cycleFlash()
                } label: {
                    Image(systemName: model.flashMode.symbolName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(model.flashMode == .off ? .white : Theme.honey)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.35), in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .disabled(model.isCapturing)
                .accessibilityLabel("Flash")
                .accessibilityValue(model.flashMode.spoken)
                .accessibilityHint("Cycles between off, automatic and on.")
            }
        }
    }

    /// Thin, rounded, and square: the classifiers centre-crop to a square
    /// before they look, so what is outside this is not seen.
    private var guide: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 20)
                .accessibilityHidden(true)

            Text("Fill the square with the flower")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.7), radius: 4)
        }
    }

    private var shutter: some View {
        Button(action: take) {
            ZStack {
                Circle()
                    .strokeBorder(Theme.honeyFill, lineWidth: 4)
                    .frame(width: 84, height: 84)
                Circle()
                    .fill(.white)
                    .frame(width: 68, height: 68)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isCapturing || model.phase != .running)
        .opacity(model.isCapturing || model.phase != .running ? 0.4 : 1)
        .accessibilityLabel("Take the photo")
        .accessibilityHint(model.isCapturing ? "Taking the photo." : "")
    }

    private func take() {
        if !reduceMotion {
            Task { @MainActor in
                model.shutterBlink = true
                try? await Task.sleep(for: .milliseconds(120))
                model.shutterBlink = false
            }
        }
        Task { @MainActor in
            if let capture = await model.capture() {
                onCapture(capture)
            }
        }
    }
}

/// Where a tap put the focus, for the moment the camera is settling there.
private struct FocusRing: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Theme.honeyFill, lineWidth: 1.5)
            .frame(width: 72, height: 72)
    }
}

/// Access refused, or never grantable. Settings is a tap away for the first;
/// for the second — Screen Time, a managed device — there is nothing a player
/// can do from here, and the screen should not pretend otherwise.
private struct DeniedView: View {

    let restricted: Bool
    let onCancel: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label(
                restricted ? "The Camera Is Restricted" : "Camera Access Is Off",
                systemImage: "camera.fill"
            )
        } description: {
            Text(
                restricted
                    ? "This device does not let FlowerPower use the camera. You can still choose a photo from your library."
                    : "FlowerPower photographs flowers for your bees, and iOS is not letting it use the camera. Turn it on in Settings, or choose a photo from your library instead."
            )
        } actions: {
            VStack(spacing: 12) {
                if !restricted {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.honey)
                    .foregroundStyle(Theme.onHoney)
                    .controlSize(.large)
                }
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .tint(Theme.honey)
                    .controlSize(.large)
            }
        }
    }
}

// MARK: - The preview layer

/// The viewfinder: a `UIView` whose layer is the session's preview layer.
///
/// SwiftUI has nothing that shows an `AVCaptureSession`, so this is the one
/// piece of UIKit left. A tap is converted to a device point here, because
/// the preview layer is the only thing that knows how its pixels map to the
/// sensor's, and both points go up: the device's for the camera, the layer's
/// for the ring that shows where it went.
private struct CameraPreview: UIViewRepresentable {

    let session: AVCaptureSession
    let isRunning: Bool
    let onTap: (_ layerPoint: CGPoint, _ devicePoint: CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onTap = onTap
        view.addGestureRecognizer(
            UITapGestureRecognizer(target: view, action: #selector(PreviewView.tapped(_:)))
        )
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.onTap = onTap
        // The connection exists only once the session has an input, which is
        // after the actor has configured it. Portrait only, like the app.
        if isRunning,
           let connection = view.previewLayer.connection,
           connection.isVideoRotationAngleSupported(90),
           connection.videoRotationAngle != 90 {
            connection.videoRotationAngle = 90
        }
    }

    final class PreviewView: UIView {

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // `layerClass` above makes this the only layer this view can have.
            layer as! AVCaptureVideoPreviewLayer
        }

        var onTap: ((CGPoint, CGPoint) -> Void)?

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            let point = gesture.location(in: self)
            onTap?(point, previewLayer.captureDevicePointConverted(fromLayerPoint: point))
        }
    }
}

// MARK: - State for the screen

/// What the screen shows, on the main actor; the camera itself is behind
/// `CameraSession`, on its queue.
@Observable
@MainActor
final class CameraModel {

    enum Phase: Equatable {
        case starting
        case running
        /// `restricted` when no setting the player can reach would change it.
        case denied(restricted: Bool)
    }

    private(set) var phase: Phase = .starting
    /// Set when the session could not be configured or started. The screen
    /// shows it once and then cancels.
    var failure: String?
    private(set) var hasFlash = false
    /// Off, not auto, to start: a flash a few centimetres from a petal is a
    /// white disc, and the lenses this is built around are chosen for close
    /// subjects. It is a tap away for the shaded hedge bottom.
    private(set) var flashMode: AVCaptureDevice.FlashMode = .off
    private(set) var isCapturing = false
    var shutterBlink = false
    /// Where the last tap landed, in the preview's coordinates, while the
    /// ring is shown there.
    private(set) var focusPoint: CGPoint?

    private let session = CameraSession()
    private var focusFade: Task<Void, Never>?

    /// For the preview layer to hang on. Nothing else outside the actor
    /// touches it.
    nonisolated var captureSession: AVCaptureSession { session.captureSession }

    func start() async {
        var status = CameraPicker.authorisationStatus
        if status == .notDetermined {
            await CameraPicker.requestAccess()
            status = CameraPicker.authorisationStatus
        }
        guard status == .authorized else {
            phase = .denied(restricted: status == .restricted)
            return
        }
        do {
            hasFlash = try await session.start()
            phase = .running
        } catch {
            failure = error.localizedDescription
        }
    }

    func stop() {
        focusFade?.cancel()
        Task { await session.stop() }
    }

    func cycleFlash() {
        switch flashMode {
        case .off: flashMode = .auto
        case .auto: flashMode = .on
        default: flashMode = .off
        }
    }

    func focus(at devicePoint: CGPoint, shownAt layerPoint: CGPoint) {
        focusPoint = layerPoint
        focusFade?.cancel()
        focusFade = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            focusPoint = nil
        }
        Task { await session.focus(at: devicePoint) }
    }

    /// One capture at a time. Returns nil if there was nothing to capture
    /// with, or the capture failed — in which case `failure` says so.
    func capture() async -> CameraCapture? {
        guard phase == .running, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        do {
            return try await session.capture(flash: flashMode)
        } catch {
            failure = error.localizedDescription
            return nil
        }
    }
}

// MARK: - The session

/// The capture session and everything that configures it, isolated to one
/// serial dispatch queue. An actor rather than a class with a queue so that
/// the compiler, not a comment, keeps the session's work off the main thread.
actor CameraSession {

    private let queue = DispatchSerialQueue(label: "com.linwoodtechnologies.flowerpower.camera")

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    /// `AVCaptureSession` is not marked Sendable, and this is read from the
    /// main thread to hand to the preview layer — the one thing Apple's own
    /// sample does with a session from outside its queue. Every other use is
    /// in this actor.
    nonisolated(unsafe) let captureSession = AVCaptureSession()

    private var device: AVCaptureDevice?
    private var output: AVCapturePhotoOutput?
    private var isConfigured = false
    /// The photo output keeps no strong reference to a capture's delegate, so
    /// this does, keyed by the settings' unique identifier, until the capture
    /// has finished.
    private var inFlight: [Int64: PhotoCaptureDelegate] = [:]
    private var subjectAreaObserver: (any NSObjectProtocol)?

    /// The best back camera the device has, in order of how many lenses iOS
    /// can choose between for us. The triple and dual-wide cameras are
    /// *virtual* devices: given one of those, iOS switches to the ultra-wide
    /// for a subject a few centimetres away — the macro mode Camera.app has —
    /// without this code knowing it happened.
    static func backCamera() -> AVCaptureDevice? {
        let preferred: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera
        ]
        let found = AVCaptureDevice.DiscoverySession(
            deviceTypes: preferred, mediaType: .video, position: .back
        ).devices
        for type in preferred {
            if let device = found.first(where: { $0.deviceType == type }) { return device }
        }
        return nil
    }

    /// Configures on first use and starts. Returns whether there is a flash
    /// to offer a toggle for.
    func start() throws -> Bool {
        if !isConfigured { try configure() }
        if !captureSession.isRunning { captureSession.startRunning() }
        guard captureSession.isRunning else { throw CameraError.couldNotStart }
        if subjectAreaObserver == nil, let device {
            // The player tapped a point, the scene changed under it — they
            // moved on to the next flower — and the camera is still staring
            // at the first one's spot. Back to continuous over the frame.
            subjectAreaObserver = NotificationCenter.default.addObserver(
                forName: AVCaptureDevice.subjectAreaDidChangeNotification,
                object: device,
                queue: nil
            ) { [weak self] _ in
                Task { await self?.resumeContinuousFocus() }
            }
        }
        return device?.hasFlash ?? false
    }

    func stop() {
        if let subjectAreaObserver {
            NotificationCenter.default.removeObserver(subjectAreaObserver)
            self.subjectAreaObserver = nil
        }
        if captureSession.isRunning { captureSession.stopRunning() }
    }

    private func configure() throws {
        guard let device = Self.backCamera() else { throw CameraError.noCamera }

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        captureSession.sessionPreset = .photo

        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else { throw CameraError.couldNotConfigure }
        captureSession.addInput(input)

        let output = AVCapturePhotoOutput()
        guard captureSession.canAddOutput(output) else { throw CameraError.couldNotConfigure }
        captureSession.addOutput(output)
        // Quality over speed: the subject does not move, and the fused,
        // noise-reduced frame is what a classifier wants to see. The default
        // photo dimensions for the `.photo` preset are kept — twelve
        // megapixels is six times what anything downstream looks at.
        output.maxPhotoQualityPrioritization = .quality
        if let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            // Portrait only, like the app.
            connection.videoRotationAngle = 90
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        // The ultra-wide bows straight stems at the edges of the frame.
        if device.isGeometricDistortionCorrectionSupported {
            device.isGeometricDistortionCorrectionEnabled = true
        }
        device.isSubjectAreaChangeMonitoringEnabled = true
        // A virtual camera that includes the ultra-wide counts zoom from the
        // ultra-wide, so factor 1 is the wide-open view and the wide lens is
        // the first switch-over factor. Start there, where Camera.app's "1×"
        // is; iOS still drops to the ultra-wide for a close subject.
        if device.constituentDevices.first?.deviceType == .builtInUltraWideCamera,
           let wide = device.virtualDeviceSwitchOverVideoZoomFactors.first {
            device.videoZoomFactor = CGFloat(truncating: wide)
        }

        self.device = device
        self.output = output
        isConfigured = true
    }

    /// Focus and exposure at a point of the sensor, from a tap. One-shot
    /// rather than continuous, so the camera settles on the flower and stays
    /// until the scene changes.
    func focus(at devicePoint: CGPoint) {
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
            device.focusPointOfInterest = devicePoint
            device.focusMode = .autoFocus
        }
        if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
            device.exposurePointOfInterest = devicePoint
            device.exposureMode = .autoExpose
        }
    }

    private func resumeContinuousFocus() {
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        let centre = CGPoint(x: 0.5, y: 0.5)
        if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusPointOfInterest = centre
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposurePointOfInterest = centre
            device.exposureMode = .continuousAutoExposure
        }
    }

    func capture(flash: AVCaptureDevice.FlashMode) async throws -> CameraCapture {
        guard let output, captureSession.isRunning else { throw CameraError.couldNotStart }

        // HEIF when the device can make one: half the bytes of a JPEG at the
        // same quality, and it is what Camera.app writes, so Photos is used
        // to it. The type goes along so Photos is told rather than left to
        // sniff.
        let usesHEIF = output.availablePhotoCodecTypes.contains(.hevc)
        let settings = usesHEIF
            ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            : AVCapturePhotoSettings()
        settings.photoQualityPrioritization = output.maxPhotoQualityPrioritization
        if output.supportedFlashModes.contains(flash) {
            settings.flashMode = flash
        }

        let data: Data = try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoCaptureDelegate(continuation: continuation) { [weak self] id in
                Task { await self?.finished(id) }
            }
            inFlight[settings.uniqueID] = delegate
            output.capturePhoto(with: settings, delegate: delegate)
        }

        // Decoding is deferred by `UIImage(data:)` until the image is drawn,
        // which `CaptureView` does off the main actor at working size.
        guard let image = UIImage(data: data) else { throw CameraError.unreadablePhoto }
        return CameraCapture(image: image, data: data, type: usesHEIF ? .heic : .jpeg)
    }

    private func finished(_ id: Int64) {
        inFlight[id] = nil
    }
}

/// Receives one photograph and hands it to the continuation waiting for it.
///
/// AVFoundation calls these in order on a queue of its own, and this object
/// is touched from nowhere else, so there is nothing here to lock.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {

    private var continuation: CheckedContinuation<Data, any Error>?
    private let onFinish: @Sendable (Int64) -> Void

    init(
        continuation: CheckedContinuation<Data, any Error>,
        onFinish: @escaping @Sendable (Int64) -> Void
    ) {
        self.continuation = continuation
        self.onFinish = onFinish
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else if let data = photo.fileDataRepresentation() {
            continuation.resume(returning: data)
        } else {
            continuation.resume(throwing: CameraError.unreadablePhoto)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: (any Error)?
    ) {
        // Normally resumed above already; this is the capture ending without
        // a photo ever being processed.
        if let continuation {
            self.continuation = nil
            continuation.resume(throwing: error ?? CameraError.unreadablePhoto)
        }
        onFinish(resolvedSettings.uniqueID)
    }
}

enum CameraError: Error, LocalizedError {
    case noCamera
    case couldNotConfigure
    case couldNotStart
    case unreadablePhoto

    var errorDescription: String? {
        switch self {
        case .noCamera: return "This device has no back camera."
        case .couldNotConfigure, .couldNotStart: return "The camera is not available right now. You can choose a photo from your library instead."
        case .unreadablePhoto: return "The photo could not be read."
        }
    }
}

// MARK: - Flash, in words and symbols

private extension AVCaptureDevice.FlashMode {
    var symbolName: String {
        switch self {
        case .off: return "bolt.slash.fill"
        case .auto: return "bolt.badge.automatic.fill"
        case .on: return "bolt.fill"
        @unknown default: return "bolt.slash.fill"
        }
    }

    var spoken: LocalizedStringKey {
        switch self {
        case .off: return "Off"
        case .auto: return "Automatic"
        case .on: return "On"
        @unknown default: return "Off"
        }
    }
}
