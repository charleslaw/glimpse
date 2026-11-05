import Foundation

public struct ImageAction: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case copyImagePath, openImageLocation, openURL, runCommand
    }

    public let id: String
    public let title: String
    public let kind: Kind
    public let executable: String?
    public let arguments: [String]?
    public let url: String?

    public init(id: String, title: String, kind: Kind, executable: String? = nil,
                arguments: [String]? = nil, url: String? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.executable = executable
        self.arguments = arguments
        self.url = url
    }

    public func expandedArguments(for file: URL) -> [String] {
        (arguments ?? []).map { expand($0, file: file, encode: false) }
    }

    public func expandedURL(for file: URL) -> URL? {
        guard let url else { return nil }
        return URL(string: expand(url, file: file, encode: true))
    }

    private func expand(_ template: String, file: URL, encode: Bool) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        func value(_ string: String) -> String {
            encode ? (string.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") : string
        }
        // Replace in one pass: a filename containing a placeholder is still literal data.
        let tokens = template.components(separatedBy: "{filepath}")
        return tokens.map {
            $0.components(separatedBy: "{filename}").joined(separator: value(file.lastPathComponent))
        }.joined(separator: value(file.path))
    }
}
