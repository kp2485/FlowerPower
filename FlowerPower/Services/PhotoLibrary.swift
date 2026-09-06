//
//  PhotoLibrary.swift
//  FlowerPower
//
//  Reading photos and, importantly, their EXIF location.
//
//  The location is what turns a photograph into a place on the map, and a place
//  into a foraging distance the colony actually pays for. It is also personal
//  data, so everything here degrades gracefully: no permission, no location, or
//  a photo with no GPS at all all leave the game entirely playable — the patch
//  simply sits at a nominal distance instead of a real one.
//

import Foundation
import Photos
import UIKit
import CoreLocation
import FlowerPowerCore

enum PhotoLibrary {

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
        options.deliveryMode = .opportunistic
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
                // The first callback is usually a degraded placeholder. Take
                // the first usable result and ignore the rest.
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard image != nil || !isDegraded, once.claim() else { return }
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
        let coordinate: GeoPoint?
    }

    /// Everything the simulation needs from a photo.
    static func metadata(for localIdentifier: String) -> PhotoMetadata? {
        guard let asset = asset(for: localIdentifier) else { return nil }

        return PhotoMetadata(
            localIdentifier: localIdentifier,
            takenAt: asset.creationDate ?? Date(),
            coordinate: asset.location.map {
                GeoPoint(
                    latitude: $0.coordinate.latitude,
                    longitude: $0.coordinate.longitude
                )
            }
        )
    }

    /// Saves a freshly captured image and returns its metadata.
    ///
    /// - Parameter location: attached explicitly. A photo taken through
    ///   `AVCapture` carries no location of its own — that has to be supplied
    ///   from CoreLocation, and only when the player has granted it.
    static func save(
        _ image: UIImage,
        location: CLLocation?
    ) async throws -> PhotoMetadata {

        // The change block runs on Photos' own queue, so what it learns comes
        // back in a box rather than by writing to a local.
        let placeholder = Placeholder()

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
            request.location = location
            request.creationDate = Date()
            placeholder.identifier = request.placeholderForCreatedAsset?.localIdentifier
        }

        guard
            let placeholderIdentifier = placeholder.identifier,
            let saved = metadata(for: placeholderIdentifier)
        else {
            throw PhotoLibraryError.couldNotSave
        }

        return saved
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
