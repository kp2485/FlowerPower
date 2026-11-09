//
//  SharedImageStore.swift
//  FlowerPower
//
//  Where photographs the library does not hold are kept, and how a
//  photograph is made fit to leave the phone.
//
//  Deliberately not the photo library. A flower somebody sends is a picture
//  they took, and quietly filing it into the recipient's camera roll —
//  alongside their own photographs, in their iCloud backup, in the Photos
//  memories that come round next year — is not something to do to a person
//  without asking. So received images live in the app's own container, and
//  disappear with the app.
//
//  It also means importing a flower needs no permission at all, which matters:
//  the alternative is a photo-library prompt appearing the first time a friend
//  sends you something, which is a bad moment to be asking.
//
//  Files are keyed by the identifier the patch carries. A received flower's
//  is `shared:<id>` and a capture made without library access is
//  `shared:capture-<uuid>`; both are kept under the part after the prefix.
//  A photograph restored from a backup is kept under the library identifier
//  the patch already has, so that `PhotoLoader`, finding nothing in this
//  phone's library by that identifier, can look here next without the engine
//  knowing the picture moved.
//

import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers
import FlowerPowerGame
import os

enum SharedImageStore {

    private static let logger = Logger(
        subsystem: "com.linwoodtechnologies.flowerpower",
        category: "sharedImages"
    )

    /// Inside Application Support rather than the App Group: the watch has no
    /// use for these, and they would otherwise count against a container the
    /// save file also lives in.
    private static var directory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return base.appendingPathComponent("SharedFlowers", isDirectory: true)
    }

    /// The file for an identifier, whichever kind it is.
    ///
    /// The identifier may have come from another device and lands in a file
    /// path, so it is reduced to characters that cannot walk out of the
    /// directory. A `shared:` prefix is dropped first, so the same file is
    /// found whether a caller passes the share id or the patch's identifier.
    private static func url(forIdentifier identifier: String) -> URL {
        let bare = FlowerShare.isSharedIdentifier(identifier)
            ? String(identifier.dropFirst("shared:".count))
            : identifier
        let safe = bare.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
            .prefix(64)

        return directory.appendingPathComponent("\(safe).jpg")
    }

    // MARK: - Writing

    /// Keeps a received flower's picture, by its share id.
    @discardableResult
    static func store(_ data: Data, forShare id: String) -> Bool {
        keep(data, forIdentifier: FlowerShare.localIdentifier(forShare: id))
    }

    /// Keeps a photograph under the identifier its patch carries.
    @discardableResult
    static func keep(_ data: Data, forIdentifier identifier: String) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try data.write(to: url(forIdentifier: identifier), options: .atomic)
            PhotoLoader.forget(identifier)
            return true
        } catch {
            logger.error("could not keep a photograph: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Reading

    /// The stored bytes for a patch's identifier, shared or not, or nil when
    /// nothing was ever kept under it.
    static func data(forIdentifier identifier: String) -> Data? {
        try? Data(contentsOf: url(forIdentifier: identifier))
    }

    static func data(forLocalIdentifier identifier: String) -> Data? {
        guard FlowerShare.isSharedIdentifier(identifier) else { return nil }
        return data(forIdentifier: identifier)
    }

    /// Decoded through the guarded decoder, at working size. Files kept
    /// before `ReceiveFlowerView` checked what it kept are still somebody
    /// else's bytes, and the decoder bounds what they can unpack to.
    static func image(forShare id: String) -> UIImage? {
        guard let data = data(forIdentifier: FlowerShare.localIdentifier(forShare: id)) else { return nil }
        return PhotoLibrary.workingImage(from: data)
    }

    // MARK: - Sending

    /// Makes a photograph fit to leave the phone.
    ///
    /// This is a privacy step first and a size step second: keep it that way
    /// round if it is ever made faster. A camera writes the time, the device
    /// and the coordinates into a picture without being asked, the app never
    /// reads or records where a flower was found, and a `FlowerShare` has no
    /// field to put a place in — so what happens here is the only thing
    /// standing between a photograph and a location leaving the device inside
    /// it. Nothing gets out of this function with its metadata.
    ///
    /// Two ways out, chosen by what came in:
    ///
    /// - A JPEG already no larger than the limits is copied pixel for pixel
    ///   with its metadata replaced by none. ImageIO can do that without
    ///   decoding, so a flower a friend sent can be passed on exactly as it
    ///   arrived instead of losing a generation to a second compression.
    ///   Only the orientation tag is written back, or the picture would turn
    ///   on its side.
    /// - Anything else — a camera original, a HEIC, a PNG, something too big
    ///   — is decoded upright at no more than `maximumDimension` on its long
    ///   edge and encoded as a fresh JPEG with no metadata at all, stepping
    ///   the quality and then the size down until it fits under `limit`.
    ///
    /// `nil` only for something that is not an image, or that claims more
    /// pixels than any photograph has.
    static func prepareForSharing(
        _ data: Data,
        maximumDimension: CGFloat = 2_048,
        quality: CGFloat = 0.85,
        limit: Int = FlowerShare.maximumImageBytes
    ) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let size = PhotoLibrary.pixelSize(of: source)
        else { return nil }

        if data.count <= limit,
           max(size.width, size.height) <= maximumDimension,
           let type = CGImageSourceGetType(source), UTType(type as String) == .jpeg,
           let stripped = strippingMetadata(from: source), stripped.count <= limit {
            return stripped
        }

        var dimension = maximumDimension
        var quality = quality
        while true {
            guard let image = PhotoLibrary.workingImage(from: source, maxPixelSize: dimension)?.cgImage,
                  let encoded = jpeg(image, quality: quality)
            else { return nil }
            if encoded.count <= limit { return encoded }

            // A busy photograph at 2,048 pixels and 0.85 is usually under
            // two megabytes; a few steps down gets anything under the cap.
            if quality > 0.66 {
                quality -= 0.1
            } else if dimension > 1_024 {
                dimension = max(1_024, dimension - 512)
                quality = 0.8
            } else {
                return nil
            }
        }
    }

    /// The pixels as they are, the metadata gone, the orientation kept.
    private static func strippingMetadata(from source: CGImageSource) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }

        var options: [CFString: Any] = [
            // An empty set, and no merging with what was there: everything
            // the camera wrote goes, including the EXIF thumbnail that would
            // otherwise carry a tiny copy of the picture's own metadata.
            kCGImageDestinationMetadata: CGImageMetadataCreateMutable(),
            kCGImageDestinationMergeMetadata: false,
            kCGImageMetadataShouldExcludeGPS: true,
            kCGImageMetadataShouldExcludeXMP: true
        ]
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let orientation = properties[kCGImagePropertyOrientation] as? UInt32 {
            options[kCGImageDestinationOrientation] = orientation
        }

        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil) else {
            return nil
        }
        return output as Data
    }

    /// A JPEG of these pixels and nothing else. `CGImageDestination` rather
    /// than `UIImage.jpegData`, so there is no `UIImage` in the middle to
    /// write a DPI or an orientation block of its own.
    private static func jpeg(_ image: CGImage, quality: CGFloat) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Writes a share to a temporary file for the share sheet to pick up.
    ///
    /// A file rather than raw `Data`, because the filename is what the
    /// recipient sees in the message and what carries the extension the app
    /// is registered to open.
    static func temporaryFile(for share: FlowerShare) throws -> URL {
        let name = share.species?.commonName ?? "Flower"
        let safeName = name.replacingOccurrences(of: "/", with: "-")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName).\(FlowerShare.fileExtension)")

        try share.encoded().write(to: url, options: .atomic)
        return url
    }
}
