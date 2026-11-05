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
        return try read(fileURL)
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
        var backup: URL?
        if FileManager.default.fileExists(atPath: url.path) {
            let copy = url.deletingLastPathComponent().appendingPathComponent("actions-backup-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: url, to: copy)
            backup = copy
        }
        try writeDefaults(to: url)
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
        let data: Data
        do { data = try BoundedLocalFileReader.read(url, maximumBytes: 65_536) }
        catch { throw ActionsConfigurationError.invalid("Choose a readable, regular local JSON file no larger than 64 KB.") }
        return try ActionsConfiguration.decode(data)
    }
}
