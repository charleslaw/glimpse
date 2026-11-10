import AppKit
import Darwin
import GlimpseCore

@MainActor
final class ActionRunner {
    private var pipelines: [UUID: ProcessPipeline] = [:]

    func run(_ action: ImageAction, file: URL, skipConfirmation: Bool = false) {
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
                if !skipConfirmation, action.url?.contains("{") == true {
                    guard confirm(title: action.title,
                                  details: "This opens \(url.host ?? "the website") with information about your selected file.\n\n\(url.absoluteString)",
                                  button: "Open Website") else { return }
                }
                guard NSWorkspace.shared.open(url) else { throw Failure.message("The website could not be opened.") }
            case .runCommand:
                try runCommand(action, file: file, skipConfirmation: skipConfirmation)
            }
        } catch { show(error) }
    }

    func cancelAll() {
        pipelines.values.forEach { $0.cancel() }
        pipelines.removeAll()
    }

    private func runCommand(_ action: ImageAction, file: URL, skipConfirmation: Bool) throws {
        guard pipelines.count < 4 else {
            throw Failure.message("Wait for a running action to finish before starting another.")
        }
        let templates: [ActionCommand]
        if let command = action.command { templates = try ActionPipeline.parse(command).stages }
        else if let path = action.executable { templates = [ActionCommand(executable: path, arguments: action.arguments ?? [])] }
        else { throw Failure.message("The action has no command.") }
        if let template = templates.first, template.executable == "google-lens" {
            try template.validateGoogleLensArguments()
            guard skipConfirmation || confirm(title: action.title,
                          details: "Google Lens will open and this image will be selected in Finder. Drag it into Lens, or choose Upload a file.\n\n\(file.path)\n\nThe image is uploaded only when you submit it in the browser.",
                          button: "Open Google Lens") else { return }
            guard let url = URL(string: "https://lens.google.com/"), NSWorkspace.shared.open(url) else {
                throw Failure.message("Google Lens could not be opened.")
            }
            NSWorkspace.shared.activateFileViewerSelecting([file])
            return
        }
        let commands = try templates.map { template -> ActionCommand in
            let resolved = try template.resolved()
            let executable = URL(fileURLWithPath: resolved.executable)
            _ = try ActionsConfiguration(actions: [ImageAction(id: "stage", title: action.title, kind: .runCommand,
                                                               executable: executable.path, arguments: resolved.arguments)]).encoded()
            guard (try? executable.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw Failure.message("The configured executable is missing or is not executable: \(executable.path)")
            }
            // Do not bypass macOS download approval by launching a quarantined executable directly.
            guard getxattr(executable.path, "com.apple.quarantine", nil, 0, 0, 0) < 0, errno == ENOATTR else {
                throw Failure.message("This executable is quarantined or could not be checked. Inspect and approve it in macOS before using it here.")
            }
            // Parsing happened before substitution: filename characters never become operators.
            return ActionCommand(executable: executable.path, arguments: resolved.expandedArguments(for: file))
        }
        guard commands.flatMap(\.arguments).reduce(0, { $0 + $1.utf8.count }) <= 131_072 else {
            throw Failure.message("The expanded command arguments are too large.")
        }
        let details = commands.map { command in
            command.executable + " " + command.arguments.map { String(reflecting: $0) }.joined(separator: " ")
        }.joined(separator: "\n  | ")
        guard skipConfirmation || confirm(title: action.title,
                      details: "This runs commands from your actions file.\n\nFolder: \(file.deletingLastPathComponent().path)\n\n\(details)",
                      button: "Run Command") else { return }
        let id = UUID()
        let pipeline = ProcessPipeline(commands: commands, directory: file.deletingLastPathComponent()) { [weak self] statuses in
            guard let self else { return }
            self.pipelines.removeValue(forKey: id)
            if let index = statuses.firstIndex(where: { $0 != 0 }) {
                self.show(Failure.message("\(commands[index].executable) exited with status \(statuses[index])."))
            }
        }
        try pipeline.start()
        pipelines[id] = pipeline
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
