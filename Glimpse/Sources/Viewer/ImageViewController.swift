import AppKit
import GlimpseCore

@MainActor
final class ImageViewController: NSViewController {

    // MARK: - Properties

    private let scrollView = ZoomableScrollView()
    private let imageView = NSImageView()
    private var navigator: FileNavigator?
    private var currentImageSize: NSSize = .zero
    private let repository = ImageRepository()
    private var imageTask: Task<Void, Never>?
    private var requestID = UUID()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let preferences: ZoomPreferences
    private var windowResizeObserver: NotificationObservation?

    var currentImageURL: URL? { navigator?.currentURL }

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
        imageView.animates = true
        errorLabel.isHidden = true
        errorLabel.textColor = .secondaryLabelColor
        errorLabel.alignment = .center
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            errorLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            errorLabel.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.8),
        ])

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
        windowResizeObserver = NotificationObservation(name: NSWindow.didResizeNotification, object: view.window) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.preferences.mode == .bestFit else { return }
                self.zoomBestFit()
            }
        }
    }

    deinit {
        imageTask?.cancel()
    }

    // MARK: - Public

    func loadImage(at url: URL) {
        requestImage(at: url, includeNavigation: true)
    }

    func applyZoomMode() {
        guard currentImageSize.width > 0, currentImageSize.height > 0 else { return }
        applyZoom(imageSize: currentImageSize)
        refreshTitle()
    }

    func cancelLoading() {
        imageTask?.cancel()
        imageTask = nil
        requestID = UUID()
    }

    // MARK: - Zoom Actions

    @objc private func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
        let location = recognizer.location(in: scrollView.contentView)
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
        scrollView.minMagnification = min(0.05, scale)
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
        guard let url = navigator?.currentURL else { return }
        requestImage(at: url)
    }

    private func requestImage(at url: URL, includeNavigation: Bool = false) {
        cancelLoading()
        let id = requestID
        currentImageSize = .zero
        imageView.image = nil
        imageView.frame = .zero
        errorLabel.isHidden = true
        view.window?.title = "\(url.lastPathComponent) — Loading…"
        let repository = repository
        imageTask = Task { @MainActor [weak self] in
            do {
                let loaded = try await repository.load(url, includeNavigation: includeNavigation)
                try Task.checkCancellation()
                guard let self, self.requestID == id else { return }
                if let navigator = loaded.navigator { self.navigator = navigator }
                switch loaded.image {
                case .success(let image): self.present(image)
                case .failure(let error): self.presentFailure(error, at: url)
                }
                self.imageTask = nil
            } catch is CancellationError {
                // A newer selection or a closed window owns the UI now.
            } catch {
                guard let self, self.requestID == id else { return }
                self.presentFailure(.unsupportedOrCorrupt, at: url)
                self.imageTask = nil
            }
        }
    }

    private func present(_ image: NSImage) {
        imageView.image = image
        currentImageSize = image.size
        imageView.frame = NSRect(origin: .zero, size: image.size)
        errorLabel.isHidden = true
        applyZoom(imageSize: image.size)
        refreshTitle()
        view.window?.makeFirstResponder(view)
    }

    private func presentFailure(_ error: ImageLoadingError, at url: URL) {
        currentImageSize = .zero
        imageView.image = nil
        imageView.frame = .zero
        errorLabel.stringValue = "Cannot Open Image\n\(error.localizedDescription)"
        errorLabel.isHidden = false
        view.window?.title = url.lastPathComponent
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
        scrollView.minMagnification = min(0.05, layout.magnification)
        setMagnification(layout.magnification)
    }
}
