import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import GlimpseCore

final class ImageMetadataTests: XCTestCase {
    func testPNGReportsDimensionsBitDepthAndCompression() async throws {
        let folder = try TemporaryFolder()
        let url = try folder.image()
        let report = try await ImageMetadataReader().read(url)
        XCTAssertTrue(report.entries.contains { $0.key.hasSuffix("PixelWidth") && $0.value == "4" })
        XCTAssertTrue(report.entries.contains { $0.key == "PNG.Compression" && $0.value.contains("Deflate") })
        XCTAssertTrue(report.entries.contains { $0.key == "PNG.Bit Depth" && $0.value == "8" })
    }

    func testJPEGReportsEXIFCommentsAndQuantizationTables() async throws {
        let folder = try TemporaryFolder()
        let url = try folder.image("comment.jpg", type: .jpeg,
                                   extraProperties: [kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "hello exif"]])
        let report = try await ImageMetadataReader().read(url)
        XCTAssertTrue(report.entries.contains { $0.key.contains("UserComment") && $0.value.contains("hello exif") })
        XCTAssertTrue(report.entries.contains { $0.key == "JPEG.Coding Mode" })
        XCTAssertTrue(report.entries.contains { $0.key.hasPrefix("JPEG.Quantization Table") })
    }

    func testGIFReportsFrameCountsPaletteEntriesAndCommentExtensions() async throws {
        let folder = try TemporaryFolder()
        let url = try folder.image("animated.gif", type: .gif, frames: 2)
        var data = try Data(contentsOf: url)
        let globalCount = data[10] & 0x80 == 0 ? 0 : 1 << (Int(data[10] & 7) + 1)
        data.insert(contentsOf: [0x21, 0xfe, 5] + Array("hello".utf8) + [0], at: 13 + globalCount * 3)
        try data.write(to: url)
        let report = try await ImageMetadataReader().read(url)
        XCTAssertTrue(report.entries.contains { $0.key == "Image.Frame Count" && $0.value == "2" })
        XCTAssertTrue(report.entries.contains { $0.key == "GIF.Frame[1].Palette Entries" && (Int($0.value) ?? 0) > 0 })
        XCTAssertTrue(report.entries.contains { $0.key == "GIF.Comment[1]" && $0.value == "hello" })
    }

    func testMetadataRejectsRemoteAndInvalidFiles() async throws {
        let folder = try TemporaryFolder()
        let invalid = try folder.file("bad.jpg", data: Data("invalid".utf8))
        for url in [try XCTUnwrap(URL(string: "https://example.com/a.jpg")), invalid] {
            do { _ = try await ImageMetadataReader().read(url); XCTFail("Invalid metadata source accepted") } catch {}
        }
    }

    func testContainerInspectionHandlesEveryTruncatedPrefix() throws {
        let folder = try TemporaryFolder()
        for (name, type) in [("a.png", UTType.png), ("a.jpg", UTType.jpeg), ("a.gif", UTType.gif)] {
            let data = try Data(contentsOf: folder.image(name, type: type))
            for length in 0..<data.count {
                _ = ImageContainerMetadata.inspect(data.subdata(in: 0..<length))
            }
        }
    }

    func testContainerInspectionHandlesDeterministicMalformedInputs() {
        let signatures: [[UInt8]] = [[71, 73, 70, 56, 57, 97], [255, 216], [137, 80, 78, 71, 13, 10, 26, 10]]
        var seed: UInt64 = 42
        for iteration in 0..<1_000 {
            var data = Data(signatures[iteration % signatures.count])
            for _ in 0..<(iteration % 512) {
                seed = seed &* 6364136223846793005 &+ 1
                data.append(UInt8(truncatingIfNeeded: seed >> 32))
            }
            _ = ImageContainerMetadata.inspect(data)
        }
    }

    func testCommentFloodCannotCreateAnUnboundedMetadataReport() {
        var data = Data("GIF89a".utf8) + Data([1, 0, 1, 0, 0, 0, 0])
        var block = Data([0x21, 0xfe])
        var remaining = 4096
        while remaining > 0 {
            let length = min(remaining, 255)
            block.append(UInt8(length))
            block.append(Data(repeating: 97, count: length))
            remaining -= length
        }
        block.append(0)
        for _ in 0..<1_100 { data.append(block) }
        data.append(0x3b)
        let entries = ImageContainerMetadata.inspect(data)
        XCTAssertTrue(entries.contains { $0.key == "Inspector.Container Limit" })
        XCTAssertLessThan(entries.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }, 4 * 1024 * 1024 + 512)
    }
}
