import AppKit
import ImageIO

public protocol ImageDecoding: Sendable {
    func decode(_ url: URL) throws -> NSImage
}

public struct ImageDecodingLimits: Sendable {
    public let maximumFileBytes: Int
    public let maximumPixels: Int
    public let maximumDecodedBytes: Int
    public let maximumFrames: Int
    public let maximumTotalFramePixels: Int

    public init(maximumFileBytes: Int = 256 * 1024 * 1024,
                maximumPixels: Int = 100_000_000,
                maximumDecodedBytes: Int = 512 * 1024 * 1024,
                maximumFrames: Int = 1_000,
                maximumTotalFramePixels: Int = 200_000_000) {
        self.maximumFileBytes = maximumFileBytes
        self.maximumPixels = maximumPixels
        self.maximumDecodedBytes = maximumDecodedBytes
        self.maximumFrames = maximumFrames
        self.maximumTotalFramePixels = maximumTotalFramePixels
    }
}

public enum ImageLoadingError: Error, LocalizedError, Sendable {
    case notLocalFile, notRegularFile, fileTooLarge, unsupportedOrCorrupt, imageTooLarge, tooManyFrames

    public var errorDescription: String? {
        switch self {
        case .notLocalFile: return "Only local image files can be opened."
        case .notRegularFile: return "The selected item is not a readable image file."
        case .fileTooLarge: return "The image exceeds the file-size limit."
        case .unsupportedOrCorrupt: return "The image is damaged or its format is not supported by this Mac."
        case .imageTooLarge: return "The image exceeds the decoded-size limit."
        case .tooManyFrames: return "The image contains too many frames."
        }
    }
}

/// Validates and decodes local files. The UI calls this through ImageRepository.
public struct ImageDecoder: ImageDecoding {
    private let limits: ImageDecodingLimits

    public init(limits: ImageDecodingLimits = ImageDecodingLimits()) { self.limits = limits }

    public func decode(_ url: URL) throws -> NSImage {
        guard url.isFileURL else { throw ImageLoadingError.notLocalFile }
        let data = try readLocalFile(url.resolvingSymlinksInPath())
        guard let source = CGImageSourceCreateWithData(data as CFData,
                                                      [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ImageLoadingError.unsupportedOrCorrupt
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw ImageLoadingError.unsupportedOrCorrupt }
        guard count <= limits.maximumFrames else { throw ImageLoadingError.tooManyFrames }
        var totalPixels = 0.0
        for index in 0..<count {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
                throw ImageLoadingError.unsupportedOrCorrupt
            }
            let w = width.doubleValue, h = height.doubleValue
            guard w.isFinite, h.isFinite, w > 0, h > 0 else {
                throw ImageLoadingError.unsupportedOrCorrupt
            }
            let pixels = w * h
            let depth = (properties[kCGImagePropertyDepth] as? NSNumber)?.intValue ?? 8
            let estimatedBytesPerPixel = depth > 8 ? 16.0 : 4.0
            totalPixels += pixels
            guard pixels <= Double(limits.maximumPixels),
                  pixels * estimatedBytesPerPixel <= Double(limits.maximumDecodedBytes),
                  totalPixels <= Double(limits.maximumTotalFramePixels) else {
                throw ImageLoadingError.imageTooLarge
            }
        }
        // Retain all frames instead of flattening animations into a single CGImage.
        if count > 1 {
            guard let image = NSImage(data: data) else { throw ImageLoadingError.unsupportedOrCorrupt }
            return image
        }
        var options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true,
                                       kCGImageSourceShouldAllowFloat: true]
        let cgImage: CGImage?
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let value = properties[kCGImagePropertyOrientation] as? NSNumber,
           let orientation = CGImagePropertyOrientation(rawValue: value.uint32Value), orientation != .up {
            // ImageIO applies EXIF without a GPU/WindowServer dependency. Using the
            // original longest edge preserves full resolution in this transform API.
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
            options[kCGImageSourceCreateThumbnailFromImageAlways] = true
            options[kCGImageSourceCreateThumbnailWithTransform] = true
            options[kCGImageSourceThumbnailMaxPixelSize] = max(width, height)
            cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
        }
        guard let cgImage else { throw ImageLoadingError.unsupportedOrCorrupt }
        return NSImage(cgImage: cgImage, size: .zero)
    }

    private func readLocalFile(_ url: URL) throws -> Data {
        do { return try BoundedLocalFileReader.read(url, maximumBytes: limits.maximumFileBytes) }
        catch BoundedLocalFileReader.Failure.notLocal { throw ImageLoadingError.notLocalFile }
        catch BoundedLocalFileReader.Failure.tooLarge { throw ImageLoadingError.fileTooLarge }
        catch BoundedLocalFileReader.Failure.notRegular { throw ImageLoadingError.notRegularFile }
    }
}
