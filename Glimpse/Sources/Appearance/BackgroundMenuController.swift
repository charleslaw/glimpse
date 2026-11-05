import AppKit
import GlimpseCore

@MainActor
final class BackgroundMenuController: NSObject {
    let menu = NSMenu(title: "Background")
    private let preferences: BackgroundPreferences
    private let onChanged: () -> Void
    private var customWindow: CustomBackgroundWindowController?
    private var items: [ViewerBackgroundStyle: NSMenuItem] = [:]

    init(preferences: BackgroundPreferences, onChanged: @escaping () -> Void) {
        self.preferences = preferences
        self.onChanged = onChanged
        super.init()
        for style in ViewerBackgroundStyle.allCases {
            if style == .custom { menu.addItem(.separator()) }
            let item = menu.addItem(withTitle: style.menuTitle, action: #selector(selectBackground(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            items[style] = item
        }
        refreshSelection()
    }

    @objc private func selectBackground(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let style = ViewerBackgroundStyle(rawValue: raw) else { return }
        if style == .custom {
            if customWindow?.window?.isVisible != true {
                customWindow = CustomBackgroundWindowController(color: preferences.customColor) { [weak self] color in
                    guard let self else { return }
                    self.preferences.customColor = color
                    self.preferences.style = .custom
                    self.refreshSelection()
                    self.onChanged()
                }
            }
            customWindow?.showWindow(nil)
            customWindow?.window?.makeKeyAndOrderFront(nil)
        } else {
            preferences.style = style
            refreshSelection()
            onChanged()
        }
    }

    private func refreshSelection() {
        for (style, item) in items { item.state = preferences.style == style ? .on : .off }
    }
}
