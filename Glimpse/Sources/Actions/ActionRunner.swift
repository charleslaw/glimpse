import AppKit
import Darwin
import GlimpseCore

@MainActor
final class ActionRunner {
    private var commands: [ObjectIdentifier: Process] = [:]
    private var deadlines: [ObjectIdentifier: Task<Void, Never>] = [:]

    func run(_ action: ImageAction, file: URL) {
        do {
            // Validate even if an action was constructed without reading JSON.
            _ = try ActionsConfiguration(actions: [action]).encoded()
            switch action.kind {
            case .copyImagePath:
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            case .openImageLocation:
                NSWorkspace.shared.activateFileViewerSelecting([file])
            case .openURL:
                guard let url = action.expandedURL(for: file), url.absoluteString.count <= 32_768 else {
                    throw Failure.message("The action produced an invalid or oversized URL.")
                }
                if action.url?.contains("{") == true {
                    guard confirm(title: action.title,
                                  details: "This opens \(url.host ?? "the website") with information about your selected file.\n\n\(url.absoluteString)",
                                  button: "Open Website") else { return }
                }
                guard NSWorkspace.shared.open(url) else { throw Failure.message("The website could not be opened.") }
            case .runCommand:
                try runCommand(action, file: file)
            }
        } catch { show(error) }
    }

    func cancelAll() {
        deadlines.values.forEach { $0.cancel() }
        deadlines.removeAll()
        commands.values.filter(\.isRunning).forEach { $0.terminate() }
        commands.removeAll()
    }

    private func runCommand(_ action: ImageAction, file: URL) throws {
        guard commands.count < 4 else {
            throw Failure.message("Wait for a running action to finish before starting another.")
        }
        let template: ActionCommand
        if let command = action.command { template = try ActionCommand.parse(command) }
        else if let path = action.executable { template = ActionCommand(executable: path, arguments: action.arguments ?? []) }
        else { throw Failure.message("The action has no command.") }
        if template.executable == "google-lens" {
            try template.validateGoogleLensArguments()
            guard confirm(title: action.title,
                          details: "Google Lens will open and this image will be selected in Finder. Drag it into Lens, or choose Upload a file.\n\n\(file.path)\n\nThe image is uploaded only when you submit it in the browser.",
                          button: "Open Google Lens") else { return }
            guard let url = URL(string: "https://lens.google.com/"), NSWorkspace.shared.open(url) else {
                throw Failure.message("Google Lens could not be opened.")
            }
            NSWorkspace.shared.activateFileViewerSelecting([file])
            return
        }
        let resolved = try template.resolved()
        let executable = URL(fileURLWithPath: resolved.executable)
        _ = try ActionsConfiguration(actions: [ImageAction(id: action.id, title: action.title, kind: .runCommand,
                                                           executable: executable.path, arguments: resolved.arguments)]).encoded()
        guard (try? executable.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw Failure.message("The configured executable is missing or is not executable.")
        }
        // Do not bypass macOS download approval by launching a quarantined executable directly.
        guard getxattr(executable.path, "com.apple.quarantine", nil, 0, 0, 0) < 0, errno == ENOATTR else {
            throw Failure.message("This executable is quarantined or could not be checked. Inspect and approve it in macOS before using it here.")
        }
        let arguments = resolved.expandedArguments(for: file)
        guard arguments.reduce(0, { $0 + $1.utf8.count }) <= 131_072 else {
            throw Failure.message("The expanded command arguments are too large.")
        }
        guard confirm(title: action.title,
                      details: "This runs a command from your actions file.\n\nExecutable: \(executable.path)\nFolder: \(file.deletingLastPathComponent().path)\nArguments: \(arguments.map { String(reflecting: $0) }.joined(separator: " "))",
                      button: "Run Command") else { return }
        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = file.deletingLastPathComponent()
        // Each argument remains a single value; no shell parses substituted filenames.
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let id = ObjectIdentifier(process)
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.deadlines.removeValue(forKey: id)?.cancel()
                self.commands.removeValue(forKey: id)
                if status != 0 { self.show(Failure.message("The action exited with status \(status).")) }
            }
        }
        try process.run()
        commands[id] = process
        deadlines[id] = Task { @MainActor [weak process] in
            do { try await Task.sleep(nanoseconds: 30_000_000_000) }
            catch { return }
            if let process, process.isRunning { process.terminate() }
        }
    }

    private func confirm(title: String, details: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = details
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func show(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Action Could Not Complete"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }
}
