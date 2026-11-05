import AppKit
import GlimpseCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowControllers: [ViewerWindowController] = []
    private let preferences = ZoomPreferences()
    private var menuController: AppMenuController?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menus = AppMenuController(preferences: preferences,
                                      onOpen: { [weak self] in self?.openDocument(nil) },
                                      onZoomModeChanged: { [weak self] in
                                          self?.windowControllers.forEach { $0.applyZoomMode() }
                                      })
        menuController = menus
        menus.install()
        if windowControllers.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.windowControllers.isEmpty else { return }
                self.openDocument(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - File Opening

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        openImage(at: URL(fileURLWithPath: filename))
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames { openImage(at: URL(fileURLWithPath: filename)) }
        sender.reply(toOpenOrPrint: .success)
    }

    @IBAction func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Open Image"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ImageFormats.supportedContentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openImage(at: url)
    }

    // MARK: - Private

    private func openImage(at url: URL) {
        let wc = ViewerWindowController(preferences: preferences)
        wc.showWindow(nil)
        wc.loadImage(at: url)
        windowControllers.append(wc)

        wc.onClose = { [weak self] closed in
            self?.windowControllers.removeAll { $0 === closed }
        }
    }

}
