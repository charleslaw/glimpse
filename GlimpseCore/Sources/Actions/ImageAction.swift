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
    public let command: String?
    private var encodesID = true

    public init(id: String, title: String, kind: Kind, executable: String? = nil,
                arguments: [String]? = nil, url: String? = nil, command: String? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.executable = executable
        self.arguments = arguments
        self.url = url
        self.command = command
    }

    private enum CodingKeys: String, CodingKey { case id, title, label, kind, executable, arguments, url, cmd }

    static func configured(label: String, cmd: String, index: Int) -> ImageAction {
        var action = ImageAction(id: "action-\(index + 1)", title: label, kind: .runCommand, command: cmd)
        action.encodesID = false
        return action
    }

    public init(from decoder: Decoder) throws {
        let generatedID = "action-\((decoder.codingPath.last?.intValue ?? 0) + 1)"
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            self.init(id: generatedID, title: Self.defaultLabel(text), kind: .runCommand, command: text)
            encodesID = false
            return
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let id = try values.decodeIfPresent(String.self, forKey: .id) ?? generatedID
        let title = try values.decodeIfPresent(String.self, forKey: .label) ?? values.decodeIfPresent(String.self, forKey: .title)
        if let cmd = try values.decodeIfPresent(String.self, forKey: .cmd) {
            let kind = try values.decodeIfPresent(Kind.self, forKey: .kind)
            guard (kind == nil || kind == .runCommand), !values.contains(.executable),
                  !values.contains(.arguments), !values.contains(.url) else {
                throw ActionsConfigurationError.invalid("Use cmd or executable/arguments, not both in the same action.")
            }
            self.init(id: id, title: title ?? Self.defaultLabel(cmd), kind: .runCommand, command: cmd)
        } else {
            self.init(id: id, title: title ?? "", kind: try values.decode(Kind.self, forKey: .kind),
                      executable: try values.decodeIfPresent(String.self, forKey: .executable),
                      arguments: try values.decodeIfPresent([String].self, forKey: .arguments),
                      url: try values.decodeIfPresent(String.self, forKey: .url))
        }
        encodesID = values.contains(.id)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        if encodesID { try values.encode(id, forKey: .id) }
        if let command {
            try values.encode(title, forKey: .label)
            try values.encode(command, forKey: .cmd)
        } else {
            try values.encode(title, forKey: .title)
            try values.encode(kind, forKey: .kind)
            try values.encodeIfPresent(executable, forKey: .executable)
            try values.encodeIfPresent(arguments, forKey: .arguments)
            try values.encodeIfPresent(url, forKey: .url)
        }
    }

    private static func defaultLabel(_ command: String) -> String {
        var label = command.trimmingCharacters(in: .whitespacesAndNewlines)
        while label.utf8.count > 80 { label.removeLast() }
        return label
    }

    public func expandedArguments(for file: URL) -> [String] {
        let templates = arguments ?? command.flatMap { try? ActionPipeline.parse($0).stages.flatMap(\.arguments) } ?? []
        return templates.map { ActionPlaceholders.expand($0, file: file) }
    }

    public func expandedURL(for file: URL) -> URL? {
        guard let url else { return nil }
        return URL(string: ActionPlaceholders.expand(url, file: file, encodeURL: true))
    }
}
