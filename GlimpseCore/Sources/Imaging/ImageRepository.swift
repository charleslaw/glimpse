import AppKit

/// A freshly decoded image transferred to the main-actor viewer. The repository
/// neither retains nor mutates the NSImage after delivery; this is ownership transfer.
public struct ImageLoadResult: @unchecked Sendable {
    public let image: Result<NSImage, ImageLoadingError>
    public let navigator: FileNavigator?
}

/// Per-window worker: directory enumeration and decoding stay off the UI actor.
public actor ImageRepository {
    private let decoder: any ImageDecoding

    public init(decoder: any ImageDecoding = ImageDecoder()) { self.decoder = decoder }

    public func load(_ url: URL, includeNavigation: Bool = false) throws -> ImageLoadResult {
        try Task.checkCancellation()
        guard url.isFileURL else {
            return ImageLoadResult(image: .failure(.notLocalFile), navigator: nil)
        }
        let navigator = includeNavigation ? FileNavigator(currentURL: url) : nil
        let image: Result<NSImage, ImageLoadingError>
        do { image = .success(try autoreleasepool { try decoder.decode(url) }) }
        catch let error as ImageLoadingError { image = .failure(error) }
        catch { image = .failure(.unsupportedOrCorrupt) }
        try Task.checkCancellation()
        return ImageLoadResult(image: image, navigator: navigator)
    }
}
