import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult func file(_ name: String, data: Data = Data()) throws -> URL {
        let file = url.appendingPathComponent(name)
        try data.write(to: file)
        return file
    }

    func image(_ name: String = "image.png", type: UTType = .png,
               width: Int = 4, height: Int = 2, orientation: Int = 1, frames: Int = 1,
               extraProperties: [CFString: Any] = [:]) throws -> URL {
        let url = self.url.appendingPathComponent(name)
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, frames, nil))
        for index in 0..<frames {
            context.setFillColor(CGColor(red: CGFloat(index % 2), green: 0, blue: CGFloat((index + 1) % 2), alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let image = try XCTUnwrap(context.makeImage())
            var properties = extraProperties
            properties[kCGImagePropertyOrientation] = orientation
            if type == .gif { properties[kCGImagePropertyGIFDictionary] = [kCGImagePropertyGIFDelayTime: 0.1] }
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
