import UniformTypeIdentifiers

/// Central registry of image formats Glimpse understands.
public enum ImageFormats {

    /// File extensions used by `FileNavigator` to filter directory contents.
    public static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp",
        "tiff", "tif", "heic", "heif", "webp",
        "jp2", "jfif", "avif", "ico",
    ]

    /// Concrete UTTypes used to filter the NSOpenPanel.
    /// Uses string-literal identifiers for formats whose static UTType members
    /// were added late or vary across SDK versions.
    public static var supportedContentTypes: [UTType] {
        let identifiers = [
            "public.jpeg",
            "public.png",
            "com.compuserve.gif",
            "com.microsoft.bmp",
            "public.tiff",
            "public.heic",
            "public.heif",
            "org.webmproject.webp",
            "public.jpeg-2000",
        ]
        return identifiers.compactMap { UTType($0) }
    }
}
