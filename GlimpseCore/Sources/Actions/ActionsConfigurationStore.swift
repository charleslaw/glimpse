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
        let data: Data
        do { data = try readData(url) }
        catch BoundedLocalFileReader.Failure.tooLarge { return try recoverInvalidConfig(at: url) }
        if isBlank(data) {
            try writeDefaults(to: url)
            return .defaults
        }
        let updated: Data
        do { updated = try normalized(data, refreshHelp: false) }
        catch is CancellationError { throw CancellationError() }
        catch { return try recoverInvalidConfig(at: url) }
        if updated != data { try write(updated, to: url) }
        return try ActionsConfiguration.decode(updated)
    }

    public func editableURL() throws -> URL {
        // Loading either validates the file or preserves it in a backup before
        // restoring defaults. Never hand the editor the only copy of a config.
        _ = try load()
        let url = fileURL
        let data = try readData(url)
        let updated = try normalized(data, refreshHelp: true)
        if updated != data { try write(updated, to: url) }
        else { try backupForEditing(url) }
        return url
    }

    public func choose(_ url: URL) throws {
        _ = try read(url)
        defaults.set(url.path, forKey: pathKey)
    }

    /// Change only the preference in the latest valid on-disk config, preserving
    /// custom actions and unknown fields. Invalid files are backed up first.
    public func setSkipConfirmation(_ value: Bool) throws -> ActionsConfiguration {
        _ = try load()
        let url = fileURL
        var object = try JSONSerialization.jsonObject(with: readData(url)) as? [String: Any] ?? [:]
        object["skip_confirmation"] = value
        let updated = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let configuration = try ActionsConfiguration.decode(updated)
        try write(updated, to: url)
        return configuration
    }

    @discardableResult public func reset() throws -> URL? {
        try writeDefaults(to: fileURL)
    }

    private func recoverInvalidConfig(at url: URL) throws -> ActionsConfiguration {
        try requireRegularFile(url)
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw ActionsConfigurationError.invalid("The config is not readable. It was left untouched.")
        }
        let backup = backupURL(for: url)
        let warning = "The previous JSON was invalid and was saved in \(backup.path). To restore it, fix the formatting or configuration issue in the backup, then copy and paste its contents into this new file."
        let value = ActionsConfiguration(actions: ActionsConfiguration.defaults.actions,
                                        notes: ActionsConfiguration.requiredNotes,
                                        variables: ActionsConfiguration.standardVariables,
                                        examples: ActionsConfiguration.standardExamples,
                                        warning: warning)
        try write(value.encoded(), to: url, backup: backup)
        return value
    }

    /// Upgrade old built-ins and abbreviated tokens without discarding user fields.
    /// Validation precedes writing; recovery preserves invalid originals in backups.
    private func normalized(_ data: Data, refreshHelp: Bool) throws -> Data {
        guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let actions = object["actions"] as? [Any] else {
            _ = try ActionsConfiguration.decode(data)
            return data
        }
        func fullNames(_ template: String) -> String {
            template.replacingOccurrences(of: "{fname}", with: "{filename}")
                .replacingOccurrences(of: "{fpath}", with: "{filepath}")
                .replacingOccurrences(of: "{ppath}", with: "{parentpath}")
        }
        let migrated: [Any] = actions.map { value in
            if let command = value as? String { return fullNames(command) }
            guard var action = value as? [String: Any] else { return value }
            if let kind = action["kind"] as? String,
               kind == "copyImagePath" || kind == "openImageLocation" {
                action["label"] = action["label"] ?? action["title"] ?? (kind == "copyImagePath" ? "Copy Image Path" : "Open Image Location")
                action["cmd"] = kind == "copyImagePath" ? "echo \"{filepath}\" | pbcopy" : "open {parentpath}"
                for key in ["id", "kind", "title", "executable", "arguments", "url"] { action.removeValue(forKey: key) }
            }
            for key in ["cmd", "url"] {
                if let template = action[key] as? String { action[key] = fullNames(template) }
            }
            if let arguments = action["arguments"] as? [String] { action["arguments"] = arguments.map(fullNames) }
            if action["cmd"] != nil, action["label"] == nil, let title = action.removeValue(forKey: "title") { action["label"] = title }
            return action
        }
        let changed = !NSArray(array: actions).isEqual(to: migrated)
        object["actions"] = migrated
        if object["skip_confirmation"] == nil { object["skip_confirmation"] = false }
        if changed || refreshHelp {
            object["notes"] = ActionsConfiguration.requiredNotes
            object["variables"] = ActionsConfiguration.standardVariables
            let defaults = try JSONSerialization.jsonObject(with: ActionsConfiguration.defaults.encoded()) as? [String: Any]
            object["examples"] = defaults?["examples"]
        }
        // Avoid rewriting unchanged files (including formatting and explicit empty arrays).
        let original = try JSONSerialization.jsonObject(with: data) as? NSDictionary
        if original?.isEqual(to: object) == true {
            _ = try ActionsConfiguration.decode(data)
            return data
        }
        let updated = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        _ = try ActionsConfiguration.decode(updated)
        return updated
    }

    /// Stage the replacement first, then rename the original into a unique
    /// backup. If publishing the replacement fails, restore the original path.
    @discardableResult private func write(_ data: Data, to url: URL, backup requestedBackup: URL? = nil) throws -> URL? {
        let manager = FileManager.default
        let prepared = url.deletingLastPathComponent().appendingPathComponent(".actions-pending-\(UUID().uuidString).json")
        defer { try? manager.removeItem(at: prepared) }
        try data.write(to: prepared, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: prepared.path)
        var backup: URL?
        // attributesOfItem does not follow symlinks. Never move a directory,
        // pipe or link and call it a byte-preserving config backup.
        if manager.fileExists(atPath: url.path) || (try? manager.attributesOfItem(atPath: url.path)) != nil {
            try requireRegularFile(url)
            let destination = requestedBackup ?? backupURL(for: url)
            try manager.moveItem(at: url, to: destination)
            backup = destination
            do { try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path) }
            catch {
                try? manager.moveItem(at: destination, to: url)
                throw error
            }
        }
        do { try manager.moveItem(at: prepared, to: url) }
        catch {
            if let backup, !manager.fileExists(atPath: url.path) {
                try? manager.moveItem(at: backup, to: url)
            }
            throw error
        }
        return backup
    }

    private func backupURL(for url: URL) -> URL {
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return url.deletingLastPathComponent().appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-backup-\(timestamp)-\(UUID().uuidString).json")
    }

    private func requireRegularFile(_ url: URL) throws {
        guard url.isFileURL,
              (try? FileManager.default.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType == .typeRegular else {
            throw ActionsConfigurationError.invalid("The config must be a regular local file. It was left untouched; choose another config file.")
        }
    }

    private func backupForEditing(_ url: URL) throws {
        try requireRegularFile(url)
        let backup = backupURL(for: url)
        try FileManager.default.copyItem(at: url, to: backup)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
    }

    private func ensureDefaultExists() throws {
        // Never recreate or overwrite a missing user-selected config silently.
        if fileURL == defaultURL, !FileManager.default.fileExists(atPath: defaultURL.path) {
            try writeDefaults(to: defaultURL)
        }
    }

    @discardableResult private func writeDefaults(to url: URL) throws -> URL? {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return try write(ActionsConfiguration.defaults.encoded(), to: url)
    }

    private func read(_ url: URL) throws -> ActionsConfiguration {
        try ActionsConfiguration.decode(readData(url))
    }

    private func readData(_ url: URL) throws -> Data {
        do { return try BoundedLocalFileReader.read(url, maximumBytes: 65_536) }
        catch is CancellationError { throw CancellationError() }
        catch BoundedLocalFileReader.Failure.tooLarge { throw BoundedLocalFileReader.Failure.tooLarge }
        catch { throw ActionsConfigurationError.invalid("Choose a readable, regular local JSON file no larger than 64 KB. The original was left untouched.") }
    }

    private func isBlank(_ data: Data) -> Bool {
        let bytes = data.starts(with: [0xef, 0xbb, 0xbf]) ? data.dropFirst(3) : data[...]
        return String(data: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
    }
}
