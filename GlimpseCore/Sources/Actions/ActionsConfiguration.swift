import Foundation

public struct ActionsConfiguration: Codable, Equatable, Sendable {
    public let version: Int
    public let actions: [ImageAction]
    public let notes: String?
    public let variables: [String: String]?
    public let examples: [ImageAction]?
    public let skipConfirmation: Bool

    public init(version: Int = 1, actions: [ImageAction], notes: String? = nil,
                variables: [String: String]? = nil, examples: [ImageAction]? = nil,
                skipConfirmation: Bool = false) {
        self.version = version
        self.actions = actions
        self.notes = notes
        self.variables = variables
        self.examples = examples
        self.skipConfirmation = skipConfirmation
    }

    public static let requiredNotes = "To reset the actions, save a blank file and Glimpse will regenerate the defaults."
    public static let standardVariables = [
        "{filename}": "The image's filename, including extension, without its directory.",
        "{filepath}": "The full local path to the image file.",
        "{parentpath}": "The full path to the image's parent directory; open {parentpath} opens that folder.",
    ]
    public static let standardExamples = [
        ImageAction.configured(label: "Open directory", cmd: "open {parentpath}", index: 0),
        ImageAction.configured(label: "Open in Chrome", cmd: "chrome {filename}", index: 1),
        ImageAction.configured(label: "Google image search", cmd: "google-lens {filepath}", index: 2),
    ]

    public static let defaults = ActionsConfiguration(actions: [
        ImageAction.configured(label: "Copy Image Path", cmd: "echo \"{filepath}\" | pbcopy", index: 0),
        ImageAction.configured(label: "Open Image Location", cmd: "open {parentpath}", index: 1),
    ], notes: requiredNotes, variables: standardVariables, examples: standardExamples)

    private enum CodingKeys: String, CodingKey {
        case version, actions, notes, variables, examples
        case skipConfirmation = "skip_confirmation"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        actions = try values.decode([ImageAction].self, forKey: .actions)
        skipConfirmation = values.contains(.skipConfirmation) ? try values.decode(Bool.self, forKey: .skipConfirmation) : false
        notes = try values.decodeIfPresent(String.self, forKey: .notes)
        variables = try values.decodeIfPresent([String: String].self, forKey: .variables)
        if let old = try? values.decode([String: String].self, forKey: .examples) {
            examples = old.sorted { $0.key < $1.key }.enumerated().map {
                ImageAction.configured(label: $0.element.key, cmd: $0.element.value, index: $0.offset)
            }
        } else {
            examples = try values.decodeIfPresent([ImageAction].self, forKey: .examples)
        }
    }

    public static func decode(_ data: Data) throws -> ActionsConfiguration {
        guard data.count <= 65_536 else { throw ActionsConfigurationError.invalid("Config files must be 64 KB or smaller.") }
        do {
            let value = try JSONDecoder().decode(Self.self, from: data)
            try value.validate()
            return value
        } catch let error as DecodingError {
            switch error {
            case .dataCorrupted(let context):
                let detail = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
                throw ActionsConfigurationError.invalid("Invalid JSON. \(detail ?? "Check double quotes, commas and matching brackets.")")
            case .keyNotFound(let key, let context):
                throw ActionsConfigurationError.invalid("Missing '\(key.stringValue)' at \(Self.configPath(context.codingPath)).")
            case .typeMismatch(_, let context), .valueNotFound(_, let context):
                throw ActionsConfigurationError.invalid("Invalid value at \(Self.configPath(context.codingPath)). \(context.debugDescription)")
            @unknown default:
                throw ActionsConfigurationError.invalid("The actions config is not valid version-1 JSON.")
            }
        }
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    private static func configPath(_ keys: [CodingKey]) -> String {
        keys.reduce("config") { path, key in
            key.intValue.map { path + "[\($0)]" } ?? (path + "." + key.stringValue)
        }
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
                let stages: [ActionCommand]
                if let command = action.command {
                    guard action.executable == nil, action.arguments == nil, action.url == nil else {
                        throw ActionsConfigurationError.invalid("Use cmd or executable/arguments, not both in the same action.")
                    }
                    stages = try ActionPipeline.parse(command).stages
                } else {
                    guard let path = action.executable, path.hasPrefix("/") else {
                        throw ActionsConfigurationError.invalid("Commands need a fixed, absolute executable path.")
                    }
                    stages = [ActionCommand(executable: path, arguments: action.arguments ?? [])]
                }
                for stage in stages {
                    if stage.executable == "google-lens" {
                        guard stages.count == 1 else { throw ActionsConfigurationError.invalid("Use google-lens as a standalone action, not in a pipeline.") }
                        try stage.validateGoogleLensArguments()
                    }
                    try validateCommand(stage)
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

    private func validateCommand(_ stage: ActionCommand) throws {
        let executable = stage.executable, arguments = stage.arguments
        guard executable.hasPrefix("/") || ActionCommand.isBareExecutable(executable) else {
            throw ActionsConfigurationError.invalid("Use a command name or an absolute executable path.")
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
    }

}

public enum ActionsConfigurationError: Error, LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}
