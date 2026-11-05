import Foundation

public struct ImageWindowLayout {
    public let contentSize: CGSize
    public let magnification: CGFloat
}

/// Pure geometry: no windows, preferences, or image decoding.
public enum ImageSizing {
    public static func fitMagnification(image: CGSize, viewport: CGSize,
                                        maximum: CGFloat = 1) -> CGFloat? {
        guard valid(image), valid(viewport), maximum.isFinite, maximum > 0 else { return nil }
        return min(maximum, viewport.width / image.width, viewport.height / image.height)
    }

    public static func windowLayout(image: CGSize, screen: CGSize, mode: ZoomMode,
                                    maximum: CGFloat = 20) -> ImageWindowLayout? {
        let available = CGSize(width: screen.width * 0.9, height: screen.height * 0.9)
        guard valid(image), valid(available), maximum.isFinite, maximum >= 1 else { return nil }
        if mode == .actualSize {
            return ImageWindowLayout(
                contentSize: CGSize(width: max(200, min(image.width, available.width)),
                                    height: max(150, min(image.height, available.height))),
                magnification: 1)
        }
        guard let scale = fitMagnification(image: image, viewport: available,
                                           maximum: mode == .autoSize ? maximum : 1) else { return nil }
        return ImageWindowLayout(
            contentSize: CGSize(width: max(200, image.width * scale),
                                height: max(150, image.height * scale)),
            magnification: scale)
    }

    private static func valid(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}
