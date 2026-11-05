import UniformTypeIdentifiers

/// One registry serves both the file picker and folder navigation.
public enum ImageFormats {
    public static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif",
        "webp", "jp2", "jfif", "avif", "ico",
    ]

    public static var supportedContentTypes: [UTType] {
        var seen = Set<String>()
        return supportedExtensions.sorted().compactMap { ext in
            guard let type = UTType(filenameExtension: ext), type.conforms(to: .image),
                  seen.insert(type.identifier).inserted else { return nil }
            return type
        }
    }
}
