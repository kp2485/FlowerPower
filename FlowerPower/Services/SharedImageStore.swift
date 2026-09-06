//
//  SharedImageStore.swift
//  FlowerPower
//
//  Where photographs other people sent are kept.
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
//  Everything is keyed by share identifier, so `PatchSummary` refers to a
//  received flower with `shared:<id>` where one the player took carries a real
//  `PHAsset` local identifier. `PhotoThumbnail` reads the prefix and asks the
//  right place.
//

import Foundation
import UIKit
import FlowerPowerGame
import os

enum SharedImageStore {

    private static let logger = Logger(
        subsystem: "com.kylepeterson.flowerpower",
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

    private static func url(forShare id: String) -> URL {
        // The identifier came from another device and lands in a file path, so
        // it is reduced to characters that cannot walk out of the directory.
        let safe = id.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
            .prefix(64)

        return directory.appendingPathComponent("\(safe).jpg")
    }

    // MARK: - Writing

    @discardableResult
    static func store(_ data: Data, forShare id: String) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try data.write(to: url(forShare: id), options: .atomic)
            return true
        } catch {
            logger.error("could not keep a shared flower: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Reading

    static func image(forShare id: String) -> UIImage? {
        guard let data = try? Data(contentsOf: url(forShare: id)) else { return nil }
        return UIImage(data: data)
    }

    /// Takes the `shared:` identifier a patch carries rather than a bare id,
    /// so callers can pass `patch.photoLocalIdentifier` straight through.
    static func image(forLocalIdentifier identifier: String) -> UIImage? {
        guard FlowerShare.isSharedIdentifier(identifier) else { return nil }
        return image(forShare: String(identifier.dropFirst("shared:".count)))
    }

    static func data(forLocalIdentifier identifier: String) -> Data? {
        guard FlowerShare.isSharedIdentifier(identifier) else { return nil }
        let id = String(identifier.dropFirst("shared:".count))
        return try? Data(contentsOf: url(forShare: id))
    }

    // MARK: - Sending

    /// Shrinks a photograph to something reasonable to send.
    ///
    /// Re-encoding rather than forwarding the original file is what strips the
    /// EXIF — the location, the timestamp, the camera — so this is a privacy
    /// step as much as a size one. `FlowerShare` says the rest.
    static func prepareForSharing(
        _ image: UIImage,
        maximumDimension: CGFloat = 1_400,
        quality: CGFloat = 0.75
    ) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maximumDimension ? maximumDimension / longest : 1

        let target = CGSize(
            width: (image.size.width * scale).rounded(),
            height: (image.size.height * scale).rounded()
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }

        return resized.jpegData(compressionQuality: quality)
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
