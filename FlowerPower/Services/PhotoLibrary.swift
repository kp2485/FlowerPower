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

        return await withCheckedContinuation { continuation in
            var hasResumed = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // Opportunistic delivery calls back more than once, first with a
                // degraded image. Resume on the first usable result and ignore
                // the rest — resuming a continuation twice is a crash.
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !hasResumed, image != nil || !isDegraded else { return }
                hasResumed = true
                continuation.resume(returning: image)
            }
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

        var placeholderIdentifier: String?

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
            request.location = location
            request.creationDate = Date()
            placeholderIdentifier = request.placeholderForCreatedAsset?.localIdentifier
        }

        guard
            let placeholderIdentifier,
            let saved = metadata(for: placeholderIdentifier)
        else {
            throw PhotoLibraryError.couldNotSave
        }

        return saved
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
