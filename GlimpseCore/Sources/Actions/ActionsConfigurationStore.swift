import Foundation

/// Serializes config IO off the UI actor. Config data is never executed here.
public actor ActionsConfigurationStore {
    private let defaults: UserDefaults
    private let defaultURL: URL
    private let pathKey = "actionsConfigPath"

    public init(defaultURL: URL? = nil, preferencesSuite: String? = nil) {
        self.defaultURL = defaultURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Glimpse/actions.json")
        self.defaults = preferencesSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public var fileURL: URL {
        guard let path = defaults.string(forKey: pathKey), path.hasPrefix("/") else { return defaultURL }
        return URL(fileURLWithPath: path)
    }

    public func load() throws -> ActionsConfiguration {
        try ensureDefaultExists()
        let url = fileURL
        let data = try readData(url)
        // A deliberately cleared file is the reset gesture. Invalid nonblank
        // JSON and an explicit empty actions array must not be replaced.
        if isBlank(data) {
            try writeDefaults(to: url)
            return .defaults
        }
        return try ActionsConfiguration.decode(data)
    }

    public func editableURL() throws -> URL {
        try ensureDefaultExists()
        return fileURL
    }

    public func choose(_ url: URL) throws {
        _ = try read(url)
        defaults.set(url.path, forKey: pathKey)
    }

    @discardableResult public func reset() throws -> URL? {
        let url = fileURL
        let prepared = url.deletingLastPathComponent().appendingPathComponent("actions-reset-\(UUID().uuidString).json")
        try writeDefaults(to: prepared)
        defer { try? FileManager.default.removeItem(at: prepared) }
        var backup: URL?
        if FileManager.default.fileExists(atPath: url.path) {
            guard (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
                throw ActionsConfigurationError.invalid("The config path is no longer a regular file. Choose another config file.")
            }
            let copy = url.deletingLastPathComponent().appendingPathComponent("actions-backup-\(UUID().uuidString).json")
            // Rename preserves even an oversized/invalid config without copying it
            // into memory or recursively copying an unexpected directory.
            try FileManager.default.moveItem(at: url, to: copy)
            backup = copy
        }
        do { try FileManager.default.moveItem(at: prepared, to: url) }
        catch {
            if let backup, !FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.moveItem(at: backup, to: url)
            }
            throw error
        }
        return backup
    }

    private func ensureDefaultExists() throws {
        // Never recreate or overwrite a missing user-selected config silently.
        if fileURL == defaultURL, !FileManager.default.fileExists(atPath: defaultURL.path) {
            try writeDefaults(to: defaultURL)
        }
    }

    private func writeDefaults(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try ActionsConfiguration.defaults.encoded().write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func read(_ url: URL) throws -> ActionsConfiguration {
        try ActionsConfiguration.decode(readData(url))
    }

    private func readData(_ url: URL) throws -> Data {
        do { return try BoundedLocalFileReader.read(url, maximumBytes: 65_536) }
        catch { throw ActionsConfigurationError.invalid("Choose a readable, regular local JSON file no larger than 64 KB.") }
    }

    private func isBlank(_ data: Data) -> Bool {
        let bytes = data.starts(with: [0xef, 0xbb, 0xbf]) ? data.dropFirst(3) : data[...]
        return String(data: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
    }
}
