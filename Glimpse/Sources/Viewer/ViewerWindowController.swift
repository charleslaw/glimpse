import AppKit
import GlimpseCore

private extension NSToolbarItem.Identifier {
    static let zoomIn     = NSToolbarItem.Identifier("zoomIn")
    static let zoomOut    = NSToolbarItem.Identifier("zoomOut")
    static let actualSize = NSToolbarItem.Identifier("actualSize")
    static let bestFit    = NSToolbarItem.Identifier("bestFit")
}

@MainActor
final class ViewerWindowController: NSWindowController, NSWindowDelegate {
    var onClose: ((ViewerWindowController) -> Void)?
    private var metadataWindow: MetadataWindowController?

    // MARK: - Init

    convenience init(preferences: ZoomPreferences) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Glimpse"
        window.backgroundColor = .black
        window.minSize = NSSize(width: 200, height: 150)
        window.isReleasedWhenClosed = false
        window.center()

        let vc = ImageViewController(preferences: preferences)
        window.contentViewController = vc

        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbarStyle = .unified

        self.init(window: window)

        toolbar.delegate = self
        window.toolbar = toolbar
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        metadataWindow?.close()
        (contentViewController as? ImageViewController)?.cancelLoading()
        onClose?(self)
    }

    // MARK: - Public

    @objc func viewMetadata(_ sender: Any?) {
        guard let url = (contentViewController as? ImageViewController)?.currentImageURL else { return }
        if metadataWindow == nil { metadataWindow = MetadataWindowController() }
        metadataWindow?.showMetadata(for: url)
    }

    func loadImage(at url: URL) {
        (contentViewController as? ImageViewController)?.loadImage(at: url)
    }

    func applyZoomMode() {
        (contentViewController as? ImageViewController)?.applyZoomMode()
    }
}

// MARK: - NSToolbarDelegate

extension ViewerWindowController: NSToolbarDelegate {

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .zoomOut, .zoomIn, .actualSize, .bestFit]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.zoomOut, .zoomIn, .actualSize, .bestFit, .flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .zoomOut:    return makeItem(.zoomOut,    symbol: "minus.magnifyingglass", label: "Zoom Out",    action: #selector(ImageViewController.zoomOut))
        case .zoomIn:     return makeItem(.zoomIn,     symbol: "plus.magnifyingglass",  label: "Zoom In",     action: #selector(ImageViewController.zoomIn))
        case .actualSize: return makeItem(.actualSize, symbol: "1.magnifyingglass",     label: "Actual Size", action: #selector(ImageViewController.zoomActualSize))
        case .bestFit:    return makeItem(.bestFit,    symbol: "arrow.up.left.and.arrow.down.right", label: "Best Fit", action: #selector(ImageViewController.zoomBestFit))
        default: return nil
        }
    }

    private func makeItem(_ identifier: NSToolbarItem.Identifier,
                          symbol: String,
                          label: String,
                          action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.target = nil   // walks the responder chain to ViewController
        item.action = action
        return item
    }
}
