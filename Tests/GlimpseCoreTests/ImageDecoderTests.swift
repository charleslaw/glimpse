import AppKit
import Darwin
import UniformTypeIdentifiers
import XCTest
@testable import GlimpseCore

final class ImageDecoderTests: XCTestCase {
    func testDecodesPNGAndJPEGUsingPixelDimensions() throws {
        let folder = try TemporaryFolder()
        for (name, type) in [("a.png", UTType.png), ("a.jpg", UTType.jpeg)] {
            let image = try ImageDecoder().decode(folder.image(name, type: type))
            XCTAssertEqual(image.size, NSSize(width: 4, height: 2))
        }
    }

    func testAppliesEXIFRotation() throws {
        let folder = try TemporaryFolder()
        let image = try ImageDecoder().decode(folder.image("rotated.jpg", type: .jpeg, orientation: 6))
        XCTAssertEqual(image.size, NSSize(width: 2, height: 4))
    }

    func testAnimatedGIFRetainsItsFrames() throws {
        let folder = try TemporaryFolder()
        let image = try ImageDecoder().decode(folder.image("animated.gif", type: .gif, frames: 2))
        let frameCounts = image.representations.compactMap { ($0 as? NSBitmapImageRep)?.value(forProperty: .frameCount) as? NSNumber }
        XCTAssertTrue(frameCounts.contains { $0.intValue == 2 })
    }

    func testRejectsRemoteURLs() {
        XCTAssertThrowsError(try ImageDecoder().decode(URL(string: "https://example.com/image.jpg")!)) {
            XCTAssertEqual($0 as? ImageLoadingError, .notLocalFile)
        }
    }

    func testRejectsDirectoriesCorruptAndEmptyFiles() throws {
        let folder = try TemporaryFolder()
        XCTAssertThrowsError(try ImageDecoder().decode(folder.url))
        XCTAssertThrowsError(try ImageDecoder().decode(folder.file("empty.jpg")))
        XCTAssertThrowsError(try ImageDecoder().decode(folder.file("bad.png", data: Data("not an image".utf8))))
    }

    func testNamedPipeCannotBlockTheDecoder() throws {
        let folder = try TemporaryFolder()
        let pipe = folder.url.appendingPathComponent("image.jpg")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        XCTAssertThrowsError(try ImageDecoder().decode(pipe)) {
            XCTAssertEqual($0 as? ImageLoadingError, .notRegularFile)
        }
    }

    func testRejectsEncodedByteBudgetBeforeDecoding() throws {
        let folder = try TemporaryFolder()
        let url = try folder.image()
        XCTAssertThrowsError(try ImageDecoder(limits: ImageDecodingLimits(maximumFileBytes: 1)).decode(url)) {
            XCTAssertEqual($0 as? ImageLoadingError, .fileTooLarge)
        }
    }

    func testRejectsPixelAndDecodedByteBudgets() throws {
        let folder = try TemporaryFolder()
        let url = try folder.image()
        for limits in [ImageDecodingLimits(maximumPixels: 1), ImageDecodingLimits(maximumDecodedBytes: 1)] {
            XCTAssertThrowsError(try ImageDecoder(limits: limits).decode(url)) {
                XCTAssertEqual($0 as? ImageLoadingError, .imageTooLarge)
            }
        }
    }

    func testRejectsFrameCountAndTotalFramePixelBudgets() throws {
        let folder = try TemporaryFolder()
        let url = try folder.image("animated.gif", type: .gif, frames: 2)
        XCTAssertThrowsError(try ImageDecoder(limits: ImageDecodingLimits(maximumFrames: 1)).decode(url)) {
            XCTAssertEqual($0 as? ImageLoadingError, .tooManyFrames)
        }
        XCTAssertThrowsError(try ImageDecoder(limits: ImageDecodingLimits(maximumTotalFramePixels: 10)).decode(url)) {
            XCTAssertEqual($0 as? ImageLoadingError, .imageTooLarge)
        }
    }

    func testPickerRegistryIncludesPreviouslyMissingFormats() {
        let types = Set(ImageFormats.supportedContentTypes.map(\.identifier))
        for ext in ["jpg", "png", "ico", "avif"] {
            if let type = UTType(filenameExtension: ext), type.conforms(to: .image) {
                XCTAssertTrue(types.contains(type.identifier), ext)
            }
        }
    }
}
