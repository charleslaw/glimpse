import Foundation

public struct ActionsConfiguration: Codable, Equatable, Sendable {
    public let version: Int
    public let actions: [ImageAction]
    public let notes: String?
    public let variables: [String: String]?
    public let examples: [String: String]?

    public init(version: Int = 1, actions: [ImageAction], notes: String? = nil,
                variables: [String: String]? = nil, examples: [String: String]? = nil) {
        self.version = version
        self.actions = actions
        self.notes = notes
        self.variables = variables
        self.examples = examples
    }

    public static let requiredNotes = "To reset the actions, save a blank file and Glimpse will regenerate the defaults."
    public static let standardVariables = [
        "{filename}": "The image's filename, including extension, without its directory.",
        "{filepath}": "The full local path to the image file.",
        "{fname}": "Alias for {filename}: the filename without its directory.",
        "{fpath}": "Alias for {filepath}: the full local path to the image file.",
        "{ppath}": "The full path to the image's parent directory; open {ppath} opens that folder.",
    ]
    public static let standardExamples = [
        "Open directory": "open {ppath}",
        "Open in Chrome": "chrome {fname}",
        "Google image search": "google-lens {filepath}",
    ]

    public static let defaults = ActionsConfiguration(actions: [
        ImageAction(id: "copy-image-path", title: "Copy Image Path", kind: .copyImagePath),
        ImageAction(id: "open-image-location", title: "Open Image Location", kind: .openImageLocation),
    ], notes: requiredNotes, variables: standardVariables, examples: standardExamples)

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
        guard (notes?.utf8.count ?? 0) <= 8_192 else {
            throw ActionsConfigurationError.invalid("Config notes must be 8 KB or smaller.")
        }
        guard version == 1, actions.count <= 64 else { throw ActionsConfigurationError.invalid("Use version 1 with at most 64 actions.") }
        var ids = Set<String>()
        for action in actions {
            guard !action.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  action.id.utf8.count <= 80, ids.insert(action.id).inserted,
                  !action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  action.title.utf8.count <= 80,
                  !action.title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  !action.id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw ActionsConfigurationError.invalid("Each action needs a unique id and a short title.")
            }
            switch action.kind {
            case .copyImagePath, .openImageLocation: break
            case .runCommand:
                let executable: String
                let arguments: [String]
                if let command = action.command {
                    guard action.executable == nil, action.arguments == nil, action.url == nil else {
                        throw ActionsConfigurationError.invalid("Use cmd or executable/arguments, not both in the same action.")
                    }
                    let parsed = try ActionCommand.parse(command)
                    guard parsed.executable.hasPrefix("/") || ActionCommand.isBareExecutable(parsed.executable) else {
                        throw ActionsConfigurationError.invalid("Use a command name or an absolute executable path.")
                    }
                    executable = parsed.executable
                    arguments = parsed.arguments
                    if executable == "google-lens" { try parsed.validateGoogleLensArguments() }
                } else {
                    guard let path = action.executable, path.hasPrefix("/") else {
                        throw ActionsConfigurationError.invalid("Commands need a fixed, absolute executable path.")
                    }
                    executable = path
                    arguments = action.arguments ?? []
                }
                guard !executable.isEmpty,
                      !executable.contains("{"), !executable.utf8.contains(0),
                      executable.utf8.count <= 4096, arguments.count <= 32 else {
                    throw ActionsConfigurationError.invalid("Use a fixed command and at most 32 arguments.")
                }
                for argument in arguments {
                    guard argument.utf8.count <= 8192, !argument.utf8.contains(0) else {
                        throw ActionsConfigurationError.invalid("Command arguments are too long or contain a null byte.")
                    }
                    try ActionPlaceholders.validate(argument)
                }
                let name = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
                let shells: Set<String> = ["sh", "bash", "zsh", "fish", "csh", "tcsh", "ksh", "dash"]
                let interpreters: Set<String> = ["python", "node", "nodejs", "ruby", "perl", "osascript", "swift", "env", "pwsh"]
                let inlineCode = arguments.contains { argument in
                    if shells.contains(name), argument.hasPrefix("-"), !argument.hasPrefix("--"), argument.dropFirst().contains("c") { return true }
                    if shells.contains(name), argument.hasPrefix("--command") { return true }
                    if interpreters.contains(name) || name.hasPrefix("python") {
                        return ["-c", "-e", "--eval", "--execute", "-command", "-encodedcommand"].contains(argument.lowercased()) ||
                            argument.hasPrefix("--eval=") || argument.hasPrefix("--execute=") ||
                            (name == "env" && (argument == "-S" || argument.hasPrefix("--split-string")))
                    }
                    return false
                }
                guard !inlineCode else {
                    throw ActionsConfigurationError.invalid("Inline shell/interpreter code is not supported. Run a trusted script file and pass {filepath} as a separate argument.")
                }
            case .openURL:
                guard let template = action.url, template.utf8.count <= 8192,
                      let components = URLComponents(string: template), components.scheme == "https",
                      let host = components.host, !host.isEmpty, !host.contains("{"),
                      components.user == nil, components.password == nil else {
                    throw ActionsConfigurationError.invalid("URL actions need an HTTPS URL with a fixed host and no embedded credentials.")
                }
                try ActionPlaceholders.validate(template)
            }
        }
    }

}

public enum ActionsConfigurationError: Error, LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}
