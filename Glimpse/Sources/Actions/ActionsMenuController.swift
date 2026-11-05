import AppKit
import GlimpseCore
import UniformTypeIdentifiers

@MainActor
final class ActionsMenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu(title: "Actions")
    private let store = ActionsConfigurationStore()
    private let runner = ActionRunner()
    private let currentFile: () -> URL?
    private var configuration = ActionsConfiguration.defaults
    private var configError: String?
    private var reloadTask: Task<Void, Never>?

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
        let store = store
        reloadTask = Task { @MainActor [weak self] in
            do {
                let configuration = try await store.load()
                guard let self, !Task.isCancelled else { return }
                self.configuration = configuration
                self.configError = nil
                self.rebuild()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.configError = error.localizedDescription
                self.rebuild()
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
        } else {
            for action in configuration.actions {
                let item = menu.addItem(withTitle: action.title, action: #selector(runAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = action
                item.isEnabled = currentFile() != nil
            }
        }
        menu.addItem(.separator())
        // These controls are unconditional, even for empty or invalid JSON.
        addManagement("Edit Command Config…", action: #selector(editConfig))
        addManagement("Reload Actions", action: #selector(reloadActions))
        addManagement("Choose Command Config…", action: #selector(chooseConfig))
        addManagement("Reset Actions to Defaults…", action: #selector(resetConfig))
    }

    private func addManagement(_ title: String, action: Selector) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? ImageAction, let file = currentFile() else { return }
        runner.run(action, file: file)
    }

    @objc private func reloadActions() { reload() }

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

    @objc private func chooseConfig() {
        let panel = NSOpenPanel()
        panel.title = "Choose Command Config"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let store = store
        Task { @MainActor [weak self] in
            do { try await store.choose(url); self?.reload() }
            catch { self?.show(error) }
        }
    }

    @objc private func resetConfig() {
        let alert = NSAlert()
        alert.messageText = "Reset Actions to Defaults?"
        alert.informativeText = "The current config will be backed up beside the original file before restoring the two default actions."
        alert.addButton(withTitle: "Reset Actions")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let store = store
        Task { @MainActor [weak self] in
            do { try await store.reset(); self?.reload() }
            catch { self?.show(error) }
        }
    }

    private func show(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Actions Config Could Not Be Opened"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
