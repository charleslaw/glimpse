import Cocoa
import CoreImage

// MARK: - ContentView

/// NSView subclass that accepts first-responder status so keyboard events
/// are delivered to this view and bubble up to the ViewController.
private final class ContentView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

// MARK: - ZoomableScrollView

/// NSScrollView that intercepts ⌘-scroll and ⌃-scroll to zoom, passing all
/// other scroll events through normally.
private final class ZoomableScrollView: NSScrollView {
    var zoomDidChange: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) || modifiers.contains(.control) {
            guard event.scrollingDeltaY != 0 else { return }
            let factor: CGFloat = event.scrollingDeltaY > 0 ? 1.1 : (1.0 / 1.1)
            let newMag = min(maxMagnification, max(minMagnification, magnification * factor))
            setMagnification(newMag, centeredAt: convert(event.locationInWindow, from: nil))
            zoomDidChange?()
        } else {
            super.scrollWheel(with: event)
        }
    }
}

// MARK: - ViewController

final class ViewController: NSViewController {

    // MARK: - Properties

    private var scrollView: ZoomableScrollView!
    private var imageView: NSImageView!
    private var navigator: FileNavigator?
    private var currentImageSize: NSSize = .zero
    private static let ciContext = CIContext()

    // MARK: - View Lifecycle

    override func loadView() {
        let contentView = ContentView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor

        scrollView = ZoomableScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 20.0
        scrollView.backgroundColor = .black
        scrollView.drawsBackground = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        imageView = NSImageView()
        imageView.imageScaling = .scaleNone
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = imageView

        scrollView.zoomDidChange = { [weak self] in self?.refreshTitle() }

        view = contentView
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(view)
    }

    // MARK: - Public

    func loadImage(at url: URL) {
        navigator = FileNavigator(currentURL: url)
        displayCurrentImage()
    }

    // MARK: - Zoom Actions

    @objc func zoomIn() {
        setMagnification(scrollView.magnification * 1.25)
    }

    @objc func zoomOut() {
        setMagnification(scrollView.magnification / 1.25)
    }

    @objc func zoomActualSize() {
        setMagnification(1.0)
    }

    @objc func zoomBestFit() {
        guard let contentSize = view.window?.contentView?.bounds.size,
              currentImageSize.width > 0, currentImageSize.height > 0 else { return }
        let fitMag = min(contentSize.width  / currentImageSize.width,
                         contentSize.height / currentImageSize.height)
        setMagnification(fitMag)
    }

    private func setMagnification(_ mag: CGFloat) {
        scrollView.magnification = min(scrollView.maxMagnification,
                                       max(scrollView.minMagnification, mag))
        refreshTitle()
    }

    // MARK: - Keyboard Navigation

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: showPreviousImage()       // ←
        case 124: showNextImage()           // →
        case 53:  view.window?.close()      // Esc
        default:  super.keyDown(with: event)
        }
    }

    // MARK: - Private

    fileprivate func showNextImage() {
        navigator?.moveToNext()
        displayCurrentImage()
    }

    fileprivate func showPreviousImage() {
        navigator?.moveToPrevious()
        displayCurrentImage()
    }

    private func loadImage(from url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        // Animated/multi-frame formats (GIF, APNG, multi-page TIFF) need all frames loaded
        if CGImageSourceGetCount(source) > 1 {
            return NSImage(contentsOf: url)
        }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: true,
        ]
        guard var cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        // CGImageSourceCreateImageAtIndex returns raw unrotated pixels; apply EXIF orientation manually
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let rawOrientation = props[kCGImagePropertyOrientation] as? UInt32,
           let orientation = CGImagePropertyOrientation(rawValue: rawOrientation),
           orientation != .up {
            let ci = CIImage(cgImage: cgImage).oriented(orientation)
            if let corrected = ViewController.ciContext.createCGImage(ci, from: ci.extent) {
                cgImage = corrected
            }
        }

        return NSImage(cgImage: cgImage, size: .zero)
    }

    private func displayCurrentImage() {
        guard let navigator else { return }

        guard let image = loadImage(from: navigator.currentURL) else {
            currentImageSize = .zero
            imageView.image = nil
            view.window?.title = navigator.currentURL.lastPathComponent
            return
        }

        imageView.image = image
        currentImageSize = image.size
        imageView.frame = NSRect(origin: .zero, size: image.size)

        fitWindowToImage(image)
        refreshTitle()
        view.window?.makeFirstResponder(view)
    }

    private func refreshTitle() {
        guard let navigator else { return }
        let zoom = Int(round(scrollView.magnification * 100))
        let w = Int(currentImageSize.width)
        let h = Int(currentImageSize.height)
        let res = w > 0 && h > 0 ? "  \(w)×\(h)" : ""
        let base: String
        if navigator.totalCount > 1 {
            base = "\(navigator.currentURL.lastPathComponent)  (\(navigator.position) of \(navigator.totalCount))"
        } else {
            base = navigator.currentURL.lastPathComponent
        }
        view.window?.title = "\(base)\(res) — \(zoom)%"
    }

    private func fitWindowToImage(_ image: NSImage) {
        guard let window = view.window,
              let screen = window.screen ?? NSScreen.main else { return }

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let screenFrame = screen.visibleFrame
        let maxWidth  = screenFrame.width  * 0.9
        let maxHeight = screenFrame.height * 0.9

        // Scale that makes the image fill the available screen area; never exceed 1:1
        let fitMag = min(1.0, maxWidth / imageSize.width, maxHeight / imageSize.height)

        // Content area = image rendered at fitMag
        let contentWidth  = max(imageSize.width  * fitMag, 200)
        let contentHeight = max(imageSize.height * fitMag, 150)

        // Convert content size → outer window frame size (adds title bar height)
        let frameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero,
                                   size: NSSize(width: contentWidth, height: contentHeight))
        ).size

        let origin = NSPoint(
            x: screenFrame.minX + (screenFrame.width  - frameSize.width)  / 2,
            y: screenFrame.minY + (screenFrame.height - frameSize.height) / 2
        )
        window.setFrame(NSRect(origin: origin, size: frameSize), display: true, animate: false)
        scrollView.magnification = fitMag
    }
}
