//
//  PhotoLibrary.swift
//  FlowerPower
//
//  Reading photographs out of the player's library, and writing new ones into it.
//
//  Little is wanted from a photograph that is already there: its identifier,
//  which is how the garden shows it again without keeping a second copy, and
//  the date it was taken, which is the date its patch gets. Saving is the other
//  direction and the fiddlier one, because Photos will only write a format it
//  has an encoder for — so a capture is encoded here rather than handed over as
//  a `UIImage`. Either way this degrades gracefully: no permission, or an
//  original that cannot be read, leaves the game entirely playable.
//

import Foundation
import Photos
import UIKit
import ImageIO
import UniformTypeIdentifiers
import FlowerPowerGame

enum PhotoLibrary {

    // MARK: - Copies

    private static let copiesKey = "photoCopies"

    /// The copy made of a picked photograph, by the picker's identifier for
    /// it, for a player whose limited access means the original cannot be read.
    static func copy(of pickerIdentifier: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: copiesKey) as? [String: String])?[pickerIdentifier]
    }

    static func remember(copy: String, of pickerIdentifier: String) {
        var copies = UserDefaults.standard.dictionary(forKey: copiesKey) as? [String: String] ?? [:]
        copies[pickerIdentifier] = copy
        UserDefaults.standard.set(copies, forKey: copiesKey)
    }

    // MARK: - Authorisation

    /// Requests only what the app needs: adding is never required, and read
    /// access can be limited to selected photos without breaking anything.
    @discardableResult
    static func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    static var authorisationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    // MARK: - Images

    static func asset(for localIdentifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
    }

    /// Loads an image at roughly the requested size. Returns `nil` rather than
    /// throwing: a missing thumbnail is a placeholder, not an error state.
    static func thumbnail(for localIdentifier: String, size: CGSize) async -> UIImage? {
        guard let asset = asset(for: localIdentifier) else { return nil }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        // One callback, with the real pixels. Opportunistic delivery sent a
        // blurred placeholder first and the final image later, and the
        // garden briefly showed the blur on every scroll.
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast

        // Opportunistic delivery calls back more than once, and the callbacks
        // are a concurrent context, so the "have we resumed yet" flag cannot
        // be a captured `var`. It is a locked box instead: resuming a
        // continuation twice is a crash, and the crash would be a race.
        let once = Once()

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // The first callback is usually a degraded placeholder, and the
                // guard here used to accept it whenever it had an image — so
                // the garden showed blurry thumbnails and a shared flower went
                // to the friend as the placeholder. Only the final callback is
                // taken, which also carries any error as a nil image.
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded, once.claim() else { return }
                continuation.resume(returning: image)
            }
        }
    }

    /// Lets exactly one caller through, whichever gets there first.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if claimed { return false }
            claimed = true
            return true
        }
    }

    // MARK: - Metadata

    struct PhotoMetadata: Equatable, Sendable {
        let localIdentifier: String
        let takenAt: Date
    }

    /// Everything the simulation needs from a photo.
    static func metadata(for localIdentifier: String) -> PhotoMetadata? {
        guard let asset = asset(for: localIdentifier) else { return nil }

        return PhotoMetadata(
            localIdentifier: localIdentifier,
            takenAt: asset.creationDate ?? Date()
        )
    }

    /// The photograph's own file, as the library holds it: the full
    /// resolution and every byte of metadata the camera wrote. For sending
    /// and backing up, where the caller re-encodes it — nothing hands these
    /// bytes on as they are, because of that metadata. `nil` when the asset
    /// is not in this phone's library or cannot be read.
    static func originalData(for localIdentifier: String) async -> Data? {
        guard let asset = asset(for: localIdentifier) else { return nil }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current

        let once = Once()
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset, options: options
            ) { data, _, _, _ in
                guard once.claim() else { return }
                continuation.resume(returning: data)
            }
        }
    }

    /// Saves a photograph straight from the camera and returns its metadata.
    ///
    /// The camera's own bytes go to Photos — the HEIF it encoded, as
    /// Camera.app's would be — so the picture is compressed once, not decoded
    /// and compressed a second time on the way in.
    static func save(_ capture: CameraCapture) async throws -> PhotoMetadata {
        try await save(capture.image, encoded: capture.data, type: capture.type)
    }

    /// Saves an image that exists only decoded, and returns its metadata.
    ///
    /// A photo chosen from the library is not saved again — it is used as it
    /// is — unless the app cannot read it, which is when `CaptureView` falls
    /// back to a copy through here. See `CaptureView.libraryPhoto`.
    static func save(_ image: UIImage) async throws -> PhotoMetadata {

        // Encoded here, in a format we chose, rather than handing Photos the
        // `UIImage`. Given an image, Photos writes it back in the format it was
        // decoded from — and an image that came from a WebP file (anything
        // saved from the web) cannot be written, because iOS reads WebP but
        // has no encoder for it. The save failed with PHPhotosErrorDomain 3302
        // and the flower was never added: the first run on a phone,
        // 2026-09-15, reproduced in the simulator the same day.
        guard let data = image.heicData() ?? image.jpegData(compressionQuality: 0.9) else {
            throw PhotoLibraryError.couldNotSave
        }
        return try await save(image, encoded: data, type: nil)
    }

    /// `type` tells Photos what the bytes are when it is known; left nil, it
    /// works it out from the data, which it can for anything made here.
    private static func save(_ image: UIImage, encoded data: Data, type: UTType?) async throws -> PhotoMetadata {

        // The change block runs on Photos' own queue, so what it learns comes
        // back in a box rather than by writing to a local.
        let placeholder = Placeholder()
        let takenAt = Date()

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = type?.identifier
                request.addResource(with: .photo, data: data, options: options)
                request.creationDate = takenAt
                placeholder.identifier = request.placeholderForCreatedAsset?.localIdentifier
            }
            // Not fetched back to read the date: that needs read access, and
            // with add-only access the fetch came back empty, the capture
            // failed, and every retry left another copy in the camera roll.
            // The date is the one just written.
            if let identifier = placeholder.identifier {
                return PhotoMetadata(localIdentifier: identifier, takenAt: takenAt)
            }
        } catch {
            // Photos refused — access denied. Fall through to keeping it here.
        }

        // No permission must leave the game playable, so the photograph is
        // kept in the app the way a flower from a friend is, and the garden
        // reads it from there by the same prefix.
        return try keepInApp(image, encoded: data, takenAt: takenAt)
    }

    /// Keeps a photograph in the app's own container rather than the library.
    ///
    /// For a photo picked from the library that the app cannot read back:
    /// it is already in the player's library, so writing it there again asked
    /// for a second permission (to add photos) straight after the first, and
    /// on a yes left a duplicate in the camera roll. Kept here, it needs
    /// neither, and the garden shows it the same way.
    static func keepInApp(_ image: UIImage) throws -> PhotoMetadata {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw PhotoLibraryError.couldNotSave
        }
        return try keepInApp(image, encoded: data, takenAt: Date())
    }

    private static func keepInApp(_ image: UIImage, encoded data: Data, takenAt: Date) throws -> PhotoMetadata {
        let id = "capture-" + UUID().uuidString
        // Kept as the camera's own bytes when they are a format the store can
        // show, and as a JPEG of them otherwise. A re-encode here cost a
        // generation that the garden and every share afterwards inherited.
        let kept = Self.isKeepable(data) ? data : (image.jpegData(compressionQuality: 0.9) ?? data)
        guard SharedImageStore.store(kept, forShare: id) else {
            throw PhotoLibraryError.couldNotSave
        }
        return PhotoMetadata(localIdentifier: FlowerShare.localIdentifier(forShare: id), takenAt: takenAt)
    }

    /// Whether the store can show these bytes as they are: an image the
    /// guarded decoder can read, with a sensible pixel count. HEIC included —
    /// the store's files are named `.jpg`, and ImageIO reads them by content
    /// rather than by name.
    private static func isKeepable(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return pixelSize(of: source) != nil
    }

    // MARK: - Sizing

    /// The long edge a photograph is worked on at. Plenty for the classifier
    /// (BioCLIP sees 224 px) and for the screen, and a fraction of the memory
    /// of a 48-megapixel original decoded whole.
    static let workingPixelSize: CGFloat = 2048

    /// Past any photograph a phone takes, panoramas included. A `.flower` is
    /// capped in bytes, and a few megabytes of flat PNG can claim to be 30,000
    /// pixels square, which is gigabytes the moment anything decodes it.
    static let maximumPixels = 120_000_000

    /// Decodes image data straight to an image no larger than `maxPixelSize`
    /// on its long edge, with its EXIF orientation applied so the pixels are
    /// upright and `.up` is true.
    static func workingImage(from data: Data, maxPixelSize: CGFloat = workingPixelSize) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return workingImage(from: source, maxPixelSize: maxPixelSize)
    }

    /// The width and height a file claims, before anything decodes it, or
    /// nil when it is not an image or claims more pixels than any photograph
    /// has.
    static func pixelSize(of source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width.multipliedReportingOverflow(by: height).partialValue <= maximumPixels,
              width > 0, height > 0
        else { return nil }
        // Pixel width and height are of the stored pixels; an orientation of
        // 5 or above turns them on their side when the image is drawn.
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return orientation >= 5
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
    }

    static func workingImage(from source: CGImageSource, maxPixelSize: CGFloat) -> UIImage? {
        guard pixelSize(of: source) != nil else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// Decodes just enough of a file for an aspect-fill square `side` pixels
    /// across: the shorter edge comes out at least that long, the longer
    /// edge follows the photograph's own proportions, and nothing past the
    /// working size is ever decoded. A garden tile reads a few hundred
    /// kilobytes of pixels this way where it used to decode the whole file.
    static func downsampled(_ data: Data, coveringSquare side: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let size = pixelSize(of: source)
        else { return nil }
        let longer = max(size.width, size.height)
        let shorter = min(size.width, size.height)
        let needed = (side * longer / shorter).rounded(.up)
        return workingImage(from: source, maxPixelSize: min(workingPixelSize, max(needed, side)))
    }

    /// The same for an image already decoded — a camera capture. Redrawn, so
    /// the result is upright with orientation `.up` whatever the camera said.
    /// Everything downstream (Vision, the reference prints, the language
    /// model) can then take the pixels as they are; the learned prints used to
    /// be stored sideways because one of them assumed `.up` and the camera's
    /// portrait shots are `.right`.
    static func workingImage(from image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height) * image.scale
        let factor = min(1, workingPixelSize / max(longest, 1))
        let size = CGSize(
            width: (image.size.width * image.scale * factor).rounded(),
            height: (image.size.height * image.scale * factor).rounded()
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Carries the new asset's identifier out of the change block.
    private final class Placeholder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: String?
        var identifier: String? {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); defer { lock.unlock() }; stored = newValue }
        }
    }
}

enum PhotoLibraryError: Error, LocalizedError {
    case couldNotSave
    case notAuthorised

    var errorDescription: String? {
        switch self {
        case .couldNotSave: return "The photo could not be saved."
        case .notAuthorised: return "FlowerPower needs access to your photos to keep your garden."
        }
    }
}
