import Foundation

public struct MetadataEntry: Equatable, Sendable {
    public let key: String
    public let value: String
    public init(_ key: String, _ value: String) { self.key = key; self.value = value }
}

public struct ImageMetadata: Sendable {
    public let file: URL
    public let entries: [MetadataEntry]
}
