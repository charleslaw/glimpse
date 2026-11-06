import Foundation

/// Tokenizes commands and unquoted pipes before expanding file placeholders.
/// Filenames can contain quotes, pipes and shell syntax without becoming code.
public struct ActionPipeline: Equatable, Sendable {
    public let stages: [ActionCommand]

    public init(stages: [ActionCommand]) { self.stages = stages }

    public static func parse(_ command: String) throws -> ActionPipeline {
        guard command.utf8.count <= 8_192, !command.utf8.contains(0) else {
            throw ActionsConfigurationError.invalid("Commands must be 8 KB or smaller and contain no null bytes.")
        }
        var stages: [ActionCommand] = [], tokens: [String] = []
        var token = "", quote: Character?, escaped = false, started = false
        func finishToken() {
            if started { tokens.append(token); token = ""; started = false }
        }
        func finishStage() throws {
            finishToken()
            guard let executable = tokens.first, !executable.isEmpty, tokens.count <= 33 else {
                throw ActionsConfigurationError.invalid("Each side of a pipe needs a command with at most 32 arguments.")
            }
            stages.append(ActionCommand(executable: executable, arguments: Array(tokens.dropFirst())))
            tokens.removeAll()
            guard stages.count <= 4 else { throw ActionsConfigurationError.invalid("Use at most four commands in a pipeline.") }
        }
        for character in command {
            if escaped { token.append(character); escaped = false; started = true; continue }
            if character == "\\", quote != "'" { escaped = true; started = true; continue }
            if let active = quote {
                if character == active { quote = nil } else { token.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character; started = true
            } else if character == "|" {
                try finishStage()
            } else if character.isWhitespace {
                finishToken()
            } else {
                token.append(character); started = true
            }
        }
        guard quote == nil, !escaped else { throw ActionsConfigurationError.invalid("Close all quotes and escapes in the command.") }
        try finishStage()
        return ActionPipeline(stages: stages)
    }
}
