import AppKit
import GlimpseCore

@MainActor
final class AppMenuController: NSObject {
    private let preferences: ZoomPreferences
    private let onOpen: () -> Void
    private let onZoomModeChanged: () -> Void
    private var zoomModeItems: [ZoomMode: NSMenuItem] = [:]

    init(preferences: ZoomPreferences, onOpen: @escaping () -> Void,
         onZoomModeChanged: @escaping () -> Void) {
        self.preferences = preferences
        self.onOpen = onOpen
        self.onZoomModeChanged = onZoomModeChanged
    }

    @objc private func openDocument(_ sender: Any?) { onOpen() }

    @objc private func setZoomMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = ZoomMode(rawValue: raw) else { return }
        preferences.mode = mode
        for (candidate, item) in zoomModeItems {
            item.state = candidate == mode ? .on : .off
        }
        onZoomModeChanged()
    }

    func install() {
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
        let openItem = fileMenu.addItem(withTitle: "Open…",
                         action: #selector(openDocument(_:)),
                         keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window",
                         action: #selector(NSWindow.performClose(_:)),
                         keyEquivalent: "w")

        // View menu
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Zoom In",
                         action: #selector(ImageViewController.zoomIn),
                         keyEquivalent: "+")
        // Also accept ⌘= so zooming in does not require Shift on a US keyboard.
        let zoomInWithoutShift = viewMenu.addItem(withTitle: "Zoom In",
                                                  action: #selector(ImageViewController.zoomIn),
                                                  keyEquivalent: "=")
        zoomInWithoutShift.isHidden = true
        zoomInWithoutShift.allowsKeyEquivalentWhenHidden = true
        viewMenu.addItem(withTitle: "Zoom Out",
                         action: #selector(ImageViewController.zoomOut),
                         keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Actual Size",
                         action: #selector(ImageViewController.zoomActualSize),
                         keyEquivalent: "0")
        viewMenu.addItem(.separator())
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
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == preferences.mode ? .on : .off
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
