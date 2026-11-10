//
//  PhotoLoader.swift
//  FlowerPower
//
//  One place to ask for a photograph at the size it will be drawn.
//
//  Every photograph in the app used to be fetched at 400 pixels, whatever
//  was going to be done with it. That is a little small for a garden tile on
//  a 3× screen and far too small for the full-width square on a flower's
//  detail sheet, which is about 1,100 pixels across on an iPhone 17 and was
//  drawn from an image a third that size — so the one place a player went to
//  look at their photograph was the one place it was soft. Callers now say
//  how many pixels they are drawing into and get at least that many.
//
//  Three places can hold a photograph, and callers should not care which:
//  the player's library, by a `PHAsset` identifier; the app's own store, for
//  a flower a friend sent or a capture made without library access
//  (`shared:` identifiers); and, since backups began carrying photographs,
//  the app's store under a library identifier that the library on *this*
//  phone has never heard of. The last is tried whenever Photos has nothing,
//  which is also what happens when a player deletes the picture from their
//  camera roll: the backup copy, if they ever restored one, fills the gap.
//
//  Decoded images are cached by identifier and size bucket. A garden of a
//  hundred flowers scrolls the same thumbnails past many times, and a
//  received flower decoded from its JPEG on every pass was the price of
//  keeping those files whole. `NSCache` lets go under memory pressure.
//

import Foundation
import UIKit
import FlowerPowerGame

enum PhotoLoader {

    // MARK: - Sizes

    /// Requested sizes are rounded up to one of these, so a tile a few
    /// points wider than its neighbour does not decode a second copy of the
    /// same picture, and a grid that reflows by a point does not reload.
    static let buckets: [CGFloat] = [256, 512, 768, 1024, 1536, 2048]

    static func bucket(forPixels pixels: CGFloat) -> CGFloat {
        buckets.first { $0 >= pixels } ?? buckets[buckets.count - 1]
    }

    // MARK: - Cache

    /// `NSCache` is thread-safe by contract and not declared `Sendable`, so
    /// the box says so for it: every access from any actor is one locked
    /// call into Foundation.
    private final class Cache: @unchecked Sendable {
        private let cache = NSCache<NSString, UIImage>()
        init() {
            // Decoded pixels, roughly: about twenty full-screen photographs.
            cache.totalCostLimit = 96 * 1024 * 1024
        }
        func object(forKey key: NSString) -> UIImage? { cache.object(forKey: key) }
        func setObject(_ image: UIImage, forKey key: NSString, cost: Int) {
            cache.setObject(image, forKey: key, cost: cost)
        }
        func removeObject(forKey key: NSString) { cache.removeObject(forKey: key) }
    }

    private static let cache = Cache()

    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.width * cgImage.height * 4
    }

    /// Everything cached for one photograph is dropped: the picture under
    /// that identifier has changed, which only happens when a backup
    /// restores a copy of it.
    static func forget(_ identifier: String) {
        for bucket in buckets {
            cache.removeObject(forKey: key(identifier, bucket))
        }
    }

    private static func key(_ identifier: String, _ bucket: CGFloat) -> NSString {
        "\(identifier)|\(Int(bucket))" as NSString
    }

    // MARK: - Reading

    /// The photograph with its shorter edge at least `side` pixels long, so
    /// that an aspect-fill square of that many pixels is drawn from real
    /// pixels rather than stretched ones. `nil` is a placeholder, not an
    /// error: a photograph on another phone, or one since deleted.
    static func image(for identifier: String, covering side: CGFloat) async -> UIImage? {
        let bucket = bucket(forPixels: side)
        let key = key(identifier, bucket)
        if let cached = cache.object(forKey: key) { return cached }

        let image: UIImage?
        if FlowerShare.isSharedIdentifier(identifier) {
            image = await decoded(SharedImageStore.data(forIdentifier: identifier), covering: bucket)
        } else if let fromLibrary = await PhotoLibrary.thumbnail(
            for: identifier, size: CGSize(width: bucket, height: bucket)
        ) {
            image = fromLibrary
        } else {
            // Not in this phone's library. A backup may have brought a copy.
            image = await decoded(SharedImageStore.data(forIdentifier: identifier), covering: bucket)
        }

        if let image { cache.setObject(image, forKey: key, cost: cost(of: image)) }
        return image
    }

    /// The whole photograph, upright, at working size — the most the app
    /// ever holds of one in memory. For looking at it full screen.
    static func fullImage(for identifier: String) async -> UIImage? {
        guard let data = await originalData(for: identifier) else { return nil }
        return await decodedWhole(data)
    }

    /// The photograph's own bytes, wherever they are: the original file from
    /// the library, or what the app's store holds. This is the source for
    /// sending and for backing up, both of which re-encode it through
    /// `SharedImageStore.prepareForSharing` on the way out.
    static func originalData(for identifier: String) async -> Data? {
        if FlowerShare.isSharedIdentifier(identifier) {
            return SharedImageStore.data(forIdentifier: identifier)
        }
        return await PhotoLibrary.originalData(for: identifier)
            ?? SharedImageStore.data(forIdentifier: identifier)
    }

    // MARK: - Off the main actor

    @concurrent
    nonisolated private static func decoded(_ data: Data?, covering side: CGFloat) async -> UIImage? {
        guard let data else { return nil }
        return PhotoLibrary.downsampled(data, coveringSquare: side)
    }

    @concurrent
    nonisolated private static func decodedWhole(_ data: Data) async -> UIImage? {
        PhotoLibrary.workingImage(from: data)
    }
}
