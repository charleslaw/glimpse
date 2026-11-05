import Foundation

public struct ActionsConfiguration: Codable, Equatable, Sendable {
    public let version: Int
    public let actions: [ImageAction]

    public init(version: Int = 1, actions: [ImageAction]) {
        self.version = version
        self.actions = actions
    }

    public static let defaults = ActionsConfiguration(actions: [
        ImageAction(id: "copy-image-path", title: "Copy Image Path", kind: .copyImagePath),
        ImageAction(id: "open-image-location", title: "Open Image Location", kind: .openImageLocation),
    ])

    public static func decode(_ data: Data) throws -> ActionsConfiguration {
        guard data.count <= 65_536 else { throw ActionsConfigurationError.invalid("Config files must be 64 KB or smaller.") }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    private func validate() throws {
        guard version == 1, actions.count <= 64 else { throw ActionsConfigurationError.invalid("Use version 1 with at most 64 actions.") }
        var ids = Set<String>()
        for action in actions {
            guard !action.id.isEmpty, action.id.count <= 80, ids.insert(action.id).inserted,
                  !action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  action.title.count <= 80, !action.title.contains(where: { $0.isNewline }) else {
                throw ActionsConfigurationError.invalid("Each action needs a unique id and a short title.")
            }
            switch action.kind {
            case .copyImagePath, .openImageLocation: break
            case .runCommand:
                guard let executable = action.executable, executable.hasPrefix("/"),
                      !executable.contains("{"), !executable.utf8.contains(0),
                      executable.count <= 4096, (action.arguments ?? []).count <= 32 else {
                    throw ActionsConfigurationError.invalid("Commands need a fixed, absolute executable path and at most 32 arguments.")
                }
                for argument in action.arguments ?? [] {
                    guard argument.count <= 8192, !argument.utf8.contains(0) else {
                        throw ActionsConfigurationError.invalid("Command arguments are too long or contain a null byte.")
                    }
                    try validatePlaceholders(argument)
                }
            case .openURL:
                guard let template = action.url, template.count <= 8192,
                      let components = URLComponents(string: template), components.scheme == "https",
                      let host = components.host, !host.isEmpty, !host.contains("{"),
                      components.user == nil, components.password == nil else {
                    throw ActionsConfigurationError.invalid("URL actions need an HTTPS URL with a fixed host and no embedded credentials.")
                }
                try validatePlaceholders(template)
            }
        }
    }

    private func validatePlaceholders(_ text: String) throws {
        let stripped = text.replacingOccurrences(of: "{filename}", with: "")
            .replacingOccurrences(of: "{filepath}", with: "")
        guard !stripped.contains("{"), !stripped.contains("}") else {
            throw ActionsConfigurationError.invalid("Only {filename} and {filepath} placeholders are supported.")
        }
    }
}

public enum ActionsConfigurationError: Error, LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}
