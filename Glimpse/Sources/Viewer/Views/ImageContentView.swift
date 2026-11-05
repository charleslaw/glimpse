import AppKit
import GlimpseCore

@MainActor
final class ImageContentView: NSView {
    var backgroundStyle: ViewerBackgroundStyle = .checkerboard { didSet { needsDisplay = true } }
    var customColor: BackgroundRGBColor = .veryDarkGray { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        backgroundStyle.baseColor(custom: customColor).nsColor.setFill()
        dirtyRect.fill()
        guard backgroundStyle == .checkerboard else { return }
        // Draw in viewport coordinates so tiles stay the same size when zooming.
        let tile: CGFloat = 12
        let area = dirtyRect.intersection(bounds)
        guard !area.isEmpty else { return }
        let squares = NSBezierPath()
        for row in Int(floor(area.minY / tile))..<Int(ceil(area.maxY / tile)) {
            for column in Int(floor(area.minX / tile))..<Int(ceil(area.maxX / tile)) where (row + column).isMultiple(of: 2) {
                squares.appendRect(NSRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile))
            }
        }
        BackgroundRGBColor.patternAlternate.nsColor.setFill()
        squares.fill()
    }
}
