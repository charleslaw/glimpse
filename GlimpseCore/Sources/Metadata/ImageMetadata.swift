import Foundation

public struct MetadataEntry: Equatable, Sendable {
    public let key: String
    public let value: String
    public init(_ key: String, _ value: String) {
        self.key = String(key.prefix(1_024))
        self.value = value.utf8.count <= 16_384 ? value
            : String(decoding: value.utf8.prefix(16_384), as: UTF8.self) + "… [truncated]"
    }
}

public struct ImageMetadata: Sendable {
    public let file: URL
    public let entries: [MetadataEntry]
}
