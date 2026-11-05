import AppKit
import CoreImage
import ImageIO

public struct ImageDecoder {
    private static let ciContext = CIContext()

    public init() {}

    public func decode(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        // Animated/multi-frame formats (GIF, APNG, multi-page TIFF) need all frames loaded
        if CGImageSourceGetCount(source) > 1 {
            return NSImage(contentsOf: url)
        }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: true,
        ]
        guard var cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        // CGImageSourceCreateImageAtIndex returns raw unrotated pixels; apply EXIF orientation manually
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let rawOrientation = props[kCGImagePropertyOrientation] as? UInt32,
           let orientation = CGImagePropertyOrientation(rawValue: rawOrientation),
           orientation != .up {
            let ci = CIImage(cgImage: cgImage).oriented(orientation)
            if let corrected = ImageDecoder.ciContext.createCGImage(ci, from: ci.extent) {
                cgImage = corrected
            }
        }

        return NSImage(cgImage: cgImage, size: .zero)
    }

}
