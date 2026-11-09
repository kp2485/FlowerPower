//
//  PhotoPipelineTests.swift
//  FlowerPowerTests
//
//  What happens to a photograph's bytes on the way out, and how the app
//  decides where to look in one. Both need ImageIO and Vision's geometry,
//  which is why they are here rather than in the package.
//

import Testing
import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers
import FlowerPowerGame
@testable import FlowerPower

@Suite("Preparing a photograph to leave the phone")
struct PrepareForSharingTests {

    /// A JPEG with a location in it, as a camera would write one.
    private func jpegWithLocation(width: Int, height: Int, quality: CGFloat = 0.9) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        }
        let cgImage = try #require(image.cgImage)
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 0.12, kCGImagePropertyGPSLongitudeRef: "W"
            ],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifLensModel: "Test lens"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "Test phone"]
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test("A small JPEG goes out pixel for pixel with its location gone")
    func losslessStrip() throws {
        let original = try jpegWithLocation(width: 1_200, height: 900)
        #expect(try properties(of: original)[kCGImagePropertyGPSDictionary] != nil)

        let prepared = try #require(SharedImageStore.prepareForSharing(original))
        let after = try properties(of: prepared)

        #expect(after[kCGImagePropertyGPSDictionary] == nil)
        #expect((after[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifLensModel] == nil)
        #expect((after[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] == nil)
        #expect(after[kCGImagePropertyPixelWidth] as? Int == 1_200)
        #expect(after[kCGImagePropertyPixelHeight] as? Int == 900)

        // The same pixels, not a re-encode: the entropy-coded segment is
        // untouched, so the file is within a metadata block of the original.
        #expect(abs(prepared.count - original.count) < 4_096)
    }

    @Test("A camera original is brought down to the working size and loses its location")
    func downscaled() throws {
        let original = try jpegWithLocation(width: 4_032, height: 3_024)

        let prepared = try #require(SharedImageStore.prepareForSharing(original))
        let after = try properties(of: prepared)

        #expect(after[kCGImagePropertyPixelWidth] as? Int == 2_048)
        #expect(after[kCGImagePropertyPixelHeight] as? Int == 1_536)
        #expect(after[kCGImagePropertyGPSDictionary] == nil)
        #expect(prepared.count <= FlowerShare.maximumImageBytes)
    }

    @Test("The byte limit is honoured by stepping down")
    func honoursLimit() throws {
        let original = try jpegWithLocation(width: 3_000, height: 3_000)

        let prepared = try #require(SharedImageStore.prepareForSharing(original, limit: 60_000))
        #expect(prepared.count <= 60_000)
    }

    @Test("Something that is not an image is refused")
    func notAnImage() {
        #expect(SharedImageStore.prepareForSharing(Data("not a picture".utf8)) == nil)
    }

    @Test("The archive size is smaller still")
    func archiveSize() throws {
        let original = try jpegWithLocation(width: 4_032, height: 3_024)
        let small = try #require(SharedImageStore.prepareForSharing(
            original, maximumDimension: 1_024, quality: 0.8, limit: SaveArchive.maximumPhotographBytes
        ))
        #expect(try properties(of: small)[kCGImagePropertyPixelWidth] as? Int == 1_024)
        #expect(small.count <= SaveArchive.maximumPhotographBytes)
    }
}

@Suite("Sizing what is drawn")
struct PhotoLoaderSizingTests {

    @Test("Requests round up to a bucket, never down")
    func buckets() {
        #expect(PhotoLoader.bucket(forPixels: 1) == 256)
        #expect(PhotoLoader.bucket(forPixels: 256) == 256)
        #expect(PhotoLoader.bucket(forPixels: 257) == 512)
        #expect(PhotoLoader.bucket(forPixels: 1_110) == 1_536)
        #expect(PhotoLoader.bucket(forPixels: 9_000) == 2_048)
    }

    @Test("Downsampling for a square covers it with the shorter edge")
    func covering() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let wide = UIGraphicsImageRenderer(size: CGSize(width: 1_600, height: 800), format: format)
            .image { $0.fill(CGRect(x: 0, y: 0, width: 1_600, height: 800)) }
        let data = try #require(wide.jpegData(compressionQuality: 0.8))

        let image = try #require(PhotoLibrary.downsampled(data, coveringSquare: 400))
        #expect(image.size.height >= 400)
        #expect(image.size.width >= 800)
        #expect(image.size.width <= 1_600)
    }
}

@Suite("Finding the flower in the frame")
struct SalientSquareTests {

    let frame = CGSize(width: 3_000, height: 4_000)

    @Test("A subject off to one side gets a padded square around it")
    func offCentre() throws {
        let box = CGRect(x: 200, y: 400, width: 800, height: 900)
        let square = try #require(FeaturePrints.squareCrop(around: [box], in: frame))

        #expect(square.width == square.height)
        #expect(square.contains(box))
        #expect(square.width >= 900 * 1.2)
        #expect(square.minX >= 0 && square.maxX <= frame.width)
        #expect(square.minY >= 0 && square.maxY <= frame.height)
    }

    @Test("A subject that fills the frame is the centre crop, so nothing")
    func fillsTheFrame() {
        let box = CGRect(x: 100, y: 500, width: 2_800, height: 2_900)
        #expect(FeaturePrints.squareCrop(around: [box], in: frame) == nil)
    }

    @Test("A tiny blob is not zoomed into")
    func tooSmall() throws {
        let box = CGRect(x: 1_500, y: 2_000, width: 40, height: 40)
        let square = try #require(FeaturePrints.squareCrop(around: [box], in: frame))

        // Rounded to whole pixels, so within one of a third of the short edge.
        #expect(square.width >= (frame.width * 0.34).rounded(.down) - 1)
    }

    @Test("Several objects are framed together")
    func several() throws {
        let boxes = [CGRect(x: 100, y: 100, width: 300, height: 300), CGRect(x: 900, y: 900, width: 300, height: 300)]
        let square = try #require(FeaturePrints.squareCrop(around: boxes, in: frame))

        for box in boxes { #expect(square.contains(box)) }
    }

    @Test("No objects, no crop")
    func nothing() {
        #expect(FeaturePrints.squareCrop(around: [], in: frame) == nil)
    }
}

@Suite("Where a photograph is looked for")
struct PhotoLoaderFallbackTests {

    /// A backup restored on another phone keeps each picture under the
    /// library identifier its patch already carries. The library here knows
    /// nothing by that name, so the loader must look in the store next.
    @Test("A library identifier this phone does not know falls back to the store")
    func fallsBackToTheStore() async throws {
        let identifier = "TEST-\(UUID().uuidString)/L0/001"
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200), format: format)
            .image { $0.fill(CGRect(x: 0, y: 0, width: 300, height: 200)) }
        let data = try #require(picture.jpegData(compressionQuality: 0.8))

        #expect(await PhotoLoader.image(for: identifier, covering: 128) == nil)

        #expect(SharedImageStore.keep(data, forIdentifier: identifier))
        let found = try #require(await PhotoLoader.image(for: identifier, covering: 128))
        #expect(found.size.height >= 128)
        #expect(await PhotoLoader.originalData(for: identifier) == data)
    }

    @Test("A shared identifier and its bare id name the same file")
    func sharedPrefix() throws {
        let id = "gift-\(UUID().uuidString)"
        let data = Data([0xFF, 0xD8, 0xFF, 0xD9])
        #expect(SharedImageStore.store(data, forShare: id))
        #expect(SharedImageStore.data(forLocalIdentifier: FlowerShare.localIdentifier(forShare: id)) == data)
        #expect(SharedImageStore.data(forIdentifier: FlowerShare.localIdentifier(forShare: id)) == data)
    }
}
