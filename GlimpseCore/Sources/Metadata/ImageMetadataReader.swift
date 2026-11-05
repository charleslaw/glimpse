import Foundation
import ImageIO

/// Inspects container properties without decoding the raster pixels.
public actor ImageMetadataReader {
    public init() {}

    public func read(_ url: URL) throws -> ImageMetadata {
        let data = try BoundedLocalFileReader.read(url, maximumBytes: 256 * 1024 * 1024)
        guard let source = CGImageSourceCreateWithData(data as CFData,
                                                      [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ImageLoadingError.unsupportedOrCorrupt
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw ImageLoadingError.unsupportedOrCorrupt }
        var entries = [MetadataEntry("File.Name", url.lastPathComponent),
                       MetadataEntry("File.Path", url.path),
                       MetadataEntry("File.Size (bytes)", String(data.count)),
                       MetadataEntry("Image.Frame Count", String(count))]
        if let type = CGImageSourceGetType(source) { entries.append(MetadataEntry("Image.Type", type as String)) }
        var remaining = 4 * 1024 * 1024
        if let properties = CGImageSourceCopyProperties(source, nil) {
            flatten(properties, path: "Container", entries: &entries, remaining: &remaining)
        }
        for frame in 0..<min(count, 1_000) {
            try Task.checkCancellation()
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, frame, nil) {
                flatten(properties, path: "Frame[\(frame + 1)]", entries: &entries, remaining: &remaining)
            }
        }
        for entry in ImageContainerMetadata.inspect(data) {
            append(entry, entries: &entries, remaining: &remaining)
            if remaining == 0 { break }
        }
        if remaining == 0 { entries.append(MetadataEntry("Inspector.Limit", "Additional metadata exceeds the 4 MB display budget.")) }
        if count > 1_000 { entries.append(MetadataEntry("Inspector.Limit", "Only the first 1,000 frames are listed.")) }
        if entries.count >= 10_000 {
            entries = Array(entries.prefix(10_000))
            entries.append(MetadataEntry("Inspector.Limit", "Only the first 10,000 fields are listed."))
        }
        try Task.checkCancellation()
        return ImageMetadata(file: url, entries: entries)
    }

    private func flatten(_ value: Any, path: String, entries: inout [MetadataEntry],
                         remaining: inout Int, depth: Int = 0) {
        guard entries.count < 10_000, remaining > 0 else { return }
        guard depth < 32 else { append(MetadataEntry(path, "[nested data limit]"), entries: &entries, remaining: &remaining); return }
        if let dictionary = value as? [String: Any] {
            for key in dictionary.keys.sorted() {
                if let child = dictionary[key] {
                    flatten(child, path: "\(path).\(key)", entries: &entries, remaining: &remaining, depth: depth + 1)
                }
            }
        } else if let array = value as? [Any] {
            for (index, child) in array.prefix(10_000).enumerated() {
                flatten(child, path: "\(path)[\(index)]", entries: &entries, remaining: &remaining, depth: depth + 1)
            }
        } else if let data = value as? Data {
            append(MetadataEntry(path, "\(data.count) bytes; prefix: \(data.prefix(32).map { String(format: "%02x", $0) }.joined())"), entries: &entries, remaining: &remaining)
        } else {
            let text = String(describing: value)
            append(MetadataEntry(path, text), entries: &entries, remaining: &remaining)
        }
    }

    private func append(_ entry: MetadataEntry, entries: inout [MetadataEntry], remaining: inout Int) {
        let cost = entry.key.utf8.count + entry.value.utf8.count
        guard entries.count < 10_000, cost <= remaining else { remaining = 0; return }
        entries.append(entry)
        remaining -= cost
    }
}
