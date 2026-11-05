import AppKit

@MainActor
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return r }
        let docFrame = doc.frame

        if r.width > docFrame.width {
            r.origin.x = floor((docFrame.width - r.width) / 2)
        }
        if r.height > docFrame.height {
            r.origin.y = floor((docFrame.height - r.height) / 2)
        }
        return r
    }
}
