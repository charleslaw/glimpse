import AppKit

actor ImageDecodeWorker {
    /// Raster images are immutable after creation. Only the main-actor viewer
    /// draws them; cache actors retain references without accessing their state.
    struct DecodedImage: @unchecked Sendable {
        let image: NSImage
        let byteCost: Int
        let cacheable: Bool
    }

    private let decoder: any ImageDecoding
    init(decoder: any ImageDecoding) { self.decoder = decoder }

    func decode(_ url: URL) throws -> DecodedImage {
        try Task.checkCancellation()
        let result = try autoreleasepool {
            let image = try decoder.decode(url)
            let bitmaps = image.representations.compactMap { $0 as? NSBitmapImageRep }
            let animated = bitmaps.contains { (($0.value(forProperty: .frameCount) as? NSNumber)?.intValue ?? 1) > 1 }
            let measured = bitmaps.map { Double($0.bytesPerRow) * Double($0.pixelsHigh) }.max() ?? 0
            let estimate = measured > 0 ? measured : Double(image.size.width) * Double(image.size.height) * 16
            let cost = estimate.isFinite && estimate < Double(Int.max) ? max(1, Int(estimate)) : Int.max
            return DecodedImage(image: image, byteCost: cost, cacheable: !animated)
        }
        try Task.checkCancellation()
        return result
    }
}
