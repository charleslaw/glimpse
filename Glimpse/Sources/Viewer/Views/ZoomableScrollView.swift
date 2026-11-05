import AppKit

@MainActor
final class ZoomableScrollView: NSScrollView {
    var zoomDidChange: (() -> Void)?

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        zoomDidChange?()
    }

    override func scrollWheel(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) || modifiers.contains(.control) {
            guard event.scrollingDeltaY != 0 else { return }
            let factor: CGFloat = event.scrollingDeltaY > 0 ? 1.1 : (1.0 / 1.1)
            let newMag = min(maxMagnification, max(minMagnification, magnification * factor))
            setMagnification(newMag, centeredAt: contentView.convert(event.locationInWindow, from: nil))
            zoomDidChange?()
        } else {
            super.scrollWheel(with: event)
        }
    }
}
