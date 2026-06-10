import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowControllers: [WindowController] = []
    private var zoomModeItems: [ZoomMode: NSMenuItem] = [:]

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        if windowControllers.isEmpty {
            DispatchQueue.main.async { self.openDocument(nil) }
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
        if let first = filenames.first {
            openImage(at: URL(fileURLWithPath: first))
        }
    }

    @IBAction func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Open Image"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ImageLoader.supportedContentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openImage(at: url)
    }

    // MARK: - Private

    private func openImage(at url: URL) {
        let wc = WindowController()
        wc.showWindow(nil)
        wc.loadImage(at: url)
        windowControllers.append(wc)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: wc.window,
            queue: .main
        ) { [weak self, weak wc] _ in
            guard let wc else { return }
            self?.windowControllers.removeAll { $0 === wc }
        }
    }

    @objc private func setZoomMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = ZoomMode(rawValue: raw) else { return }
        ZoomMode.current = mode
        for (m, item) in zoomModeItems {
            item.state = m == mode ? .on : .off
        }
        windowControllers.forEach { $0.applyZoomMode() }
    }

    private func setupMenuBar() {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        // Application menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Glimpse",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Glimpse",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)),
                                         keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Glimpse",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        // File menu
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "Open…",
                         action: #selector(openDocument(_:)),
                         keyEquivalent: "o")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window",
                         action: #selector(NSWindow.performClose(_:)),
                         keyEquivalent: "w")

        // View menu
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        let fullScreen = viewMenu.addItem(withTitle: "Enter Full Screen",
                                          action: #selector(NSWindow.toggleFullScreen(_:)),
                                          keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]

        // Settings menu
        let settingsItem = NSMenuItem()
        mainMenu.addItem(settingsItem)
        let settingsMenu = NSMenu(title: "Settings")
        settingsItem.submenu = settingsMenu
        for mode in ZoomMode.allCases {
            let item = NSMenuItem(title: mode.menuTitle,
                                  action: #selector(setZoomMode(_:)),
                                  keyEquivalent: "")
            item.representedObject = mode.rawValue
            item.state = mode == ZoomMode.current ? .on : .off
            settingsMenu.addItem(item)
            zoomModeItems[mode] = item
        }

        // Window menu
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom",
                           action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")
    }
}
