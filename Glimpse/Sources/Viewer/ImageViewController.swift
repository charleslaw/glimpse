import AppKit
import GlimpseCore

final class ImageViewController: NSViewController {

    // MARK: - Properties

    private let scrollView = ZoomableScrollView()
    private let imageView = NSImageView()
    private var navigator: FileNavigator?
    private var currentImageSize: NSSize = .zero
    private let decoder = ImageDecoder()
    private let preferences: ZoomPreferences
    private var windowResizeObserver: NSObjectProtocol?

    init(preferences: ZoomPreferences) {
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - View Lifecycle

    override func loadView() {
        let contentView = ImageContentView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor

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

        imageView.imageScaling = .scaleNone
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let clipView = CenteringClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        scrollView.documentView = imageView

        scrollView.zoomDidChange = { [weak self] in self?.refreshTitle() }

        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        doubleClick.numberOfClicksRequired = 2
        scrollView.addGestureRecognizer(doubleClick)

        view = contentView
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(view)
        windowResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: view.window,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.preferences.mode == .bestFit else { return }
            self.zoomBestFit()
        }
    }

    deinit {
        if let observer = windowResizeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public

    func loadImage(at url: URL) {
        navigator = FileNavigator(currentURL: url)
        displayCurrentImage()
    }

    func applyZoomMode() {
        guard currentImageSize.width > 0, currentImageSize.height > 0 else { return }
        applyZoom(imageSize: currentImageSize)
        refreshTitle()
    }

    // MARK: - Zoom Actions

    @objc private func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
        let location = recognizer.location(in: scrollView)
        let newMag = min(scrollView.maxMagnification, scrollView.magnification * 2.0)
        scrollView.setMagnification(newMag, centeredAt: location)
        refreshTitle()
    }

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
        view.layoutSubtreeIfNeeded()
        guard let scale = ImageSizing.fitMagnification(image: currentImageSize,
                                                       viewport: scrollView.contentSize) else { return }
        setMagnification(scale)
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

    private func displayCurrentImage() {
        guard let navigator else { return }

        guard let image = decoder.decode(navigator.currentURL) else {
            currentImageSize = .zero
            imageView.image = nil
            view.window?.title = navigator.currentURL.lastPathComponent
            return
        }

        imageView.image = image
        currentImageSize = image.size
        imageView.frame = NSRect(origin: .zero, size: image.size)

        applyZoom(imageSize: image.size)
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

    private func applyZoom(imageSize: NSSize) {
        guard let window = view.window,
              let screen = window.screen ?? NSScreen.main,
              let layout = ImageSizing.windowLayout(image: imageSize, screen: screen.visibleFrame.size,
                                                      mode: preferences.mode,
                                                      maximum: scrollView.maxMagnification) else { return }
        let screenFrame = screen.visibleFrame
        let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: layout.contentSize)).size
        let origin = NSPoint(x: screenFrame.midX - frameSize.width / 2,
                             y: screenFrame.midY - frameSize.height / 2)
        window.setFrame(NSRect(origin: origin, size: frameSize), display: true)
        scrollView.magnification = layout.magnification
    }
}
