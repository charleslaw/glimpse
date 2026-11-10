import AppKit
import GlimpseCore

@MainActor
final class ActionsMenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu(title: "Actions")
    private let store = ActionsConfigurationStore()
    private let runner = ActionRunner()
    private let currentFile: () -> URL?
    private var configuration = ActionsConfiguration.defaults
    private var configError: String?
    private var reportedError: String?
    private var reloadTask: Task<Void, Never>?
    private var isSavingConfirmation = false

    init(currentFile: @escaping () -> URL?) {
        self.currentFile = currentFile
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        rebuild()
        reload()
    }

    deinit { reloadTask?.cancel() }

    func reload() {
        reloadTask?.cancel()
        isSavingConfirmation = false
        let store = store
        reloadTask = Task { @MainActor [weak self] in
            do {
                let configuration = try await store.load()
                guard let self, !Task.isCancelled else { return }
                self.configuration = configuration
                self.configError = nil
                self.reportedError = nil
                self.rebuild()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.configuration = .defaults
                let message = error.localizedDescription
                self.configError = message
                self.rebuild()
                guard self.reportedError != message else { return }
                self.reportedError = message
                self.showConfigError(message)
            }
        }
    }

    func cancelRunningActions() { runner.cancelAll() }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuild() }

    private func rebuild() {
        menu.removeAllItems()
        if configError != nil {
            let errorItem = menu.addItem(withTitle: "Actions config needs attention", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            errorItem.toolTip = configError
        }
        for action in configuration.actions {
            let item = menu.addItem(withTitle: action.title, action: #selector(runAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action
            item.isEnabled = currentFile() != nil
        }
        menu.addItem(.separator())
        let confirmation = menu.addItem(withTitle: "Confirm Actions", action: #selector(toggleConfirmation), keyEquivalent: "")
        confirmation.target = self
        confirmation.state = configuration.skipConfirmation ? .off : .on
        confirmation.isEnabled = configError == nil && !isSavingConfirmation
        // Editing stays available even for empty or invalid JSON.
        addManagement("Edit Command Config…", action: #selector(editConfig))
    }

    private func addManagement(_ title: String, action: Selector) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? ImageAction, let file = currentFile() else { return }
        runner.run(action, file: file, skipConfirmation: configuration.skipConfirmation)
    }

    @objc private func toggleConfirmation() {
        guard configError == nil, !isSavingConfirmation else { return }
        let skip = !configuration.skipConfirmation
        reloadTask?.cancel()
        isSavingConfirmation = true
        rebuild()
        let store = store
        reloadTask = Task { @MainActor [weak self] in
            do {
                let configuration = try await store.setSkipConfirmation(skip)
                guard let self, !Task.isCancelled else { return }
                self.configuration = configuration
                self.isSavingConfirmation = false
                self.rebuild()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.isSavingConfirmation = false
                self.rebuild()
                self.show(error)
                self.reload()
            }
        }
    }

    @objc private func editConfig() {
        let store = store
        Task { @MainActor [weak self] in
            do {
                let url = try await store.editableURL()
                if let editor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
                    _ = try await NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
                } else { NSWorkspace.shared.open(url) }
            } catch { self?.show(error) }
        }
    }

    private func show(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Actions Config Could Not Be Opened"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func showConfigError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Actions Config Needs Attention"
        alert.informativeText = "\(message)\n\nUsing the two default actions: Copy Image Path and Open Image Location.\n\nUse Edit Command Config… to fix the file. Check JSON quotes, commas and brackets, and keep version 1 with an actions array. Save a blank file to regenerate the defaults."
        alert.addButton(withTitle: "Use Default Actions")
        alert.addButton(withTitle: "Edit Command Config…")
        if alert.runModal() == .alertSecondButtonReturn { editConfig() }
    }
}
