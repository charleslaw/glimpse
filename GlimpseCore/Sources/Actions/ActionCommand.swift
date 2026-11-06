import Foundation

/// Shell-like quoting for convenience, with no shell evaluation. Tokenize the
/// template BEFORE substitution so filenames can never introduce new arguments.
public struct ActionCommand: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    public static func parse(_ command: String) throws -> ActionCommand {
        let pipeline = try ActionPipeline.parse(command)
        guard pipeline.stages.count == 1, let stage = pipeline.stages.first else {
            throw ActionsConfigurationError.invalid("This operation needs a single command, not a pipeline.")
        }
        return stage
    }

    public static func isBareExecutable(_ name: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.+-")
        return !name.isEmpty && name != "." && name != ".." && !name.hasPrefix("-") &&
            name.unicodeScalars.allSatisfy(allowed.contains)
    }

    public func expandedArguments(for file: URL) -> [String] {
        arguments.map { ActionPlaceholders.expand($0, file: file) }
    }

    public func validateGoogleLensArguments() throws {
        guard arguments.isEmpty || (arguments.count == 1 && ["{filename}", "{filepath}"].contains(arguments[0])) else {
            throw ActionsConfigurationError.invalid("Use google-lens {filepath} to prepare a search for the selected image.")
        }
    }

    /// Fixed search directories avoid a GUI app's unreliable PATH and never
    /// search the image folder. Tests can inject an isolated search directory.
    public func resolved(searchDirectories: [URL] = defaultSearchDirectories) throws -> ActionCommand {
        if executable == "chrome" {
            return ActionCommand(executable: "/usr/bin/open", arguments: ["-b", "com.google.Chrome", "--"] + arguments)
        }
        let candidates: [URL]
        if executable.hasPrefix("/") { candidates = [URL(fileURLWithPath: executable)] }
        else {
            guard Self.isBareExecutable(executable) else {
                throw ActionsConfigurationError.invalid("Use a command name or an absolute executable path.")
            }
            candidates = searchDirectories.map { $0.appendingPathComponent(executable) }
        }
        for candidate in candidates {
            let url = candidate.resolvingSymlinksInPath()
            if FileManager.default.isExecutableFile(atPath: url.path),
               (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                return ActionCommand(executable: url.path, arguments: arguments)
            }
        }
        throw ActionsConfigurationError.invalid("Command '\(executable)' was not found. Use its absolute executable path if it is installed elsewhere.")
    }

    public static let defaultSearchDirectories = ["/usr/bin", "/bin", "/usr/sbin", "/sbin", "/opt/homebrew/bin", "/usr/local/bin"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }
}
