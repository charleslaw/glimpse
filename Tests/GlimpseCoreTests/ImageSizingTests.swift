import XCTest
@testable import GlimpseCore

final class ImageSizingTests: XCTestCase {
    private let screen = CGSize(width: 1000, height: 800)

    func testBestFitNeverEnlargesSmallImages() throws {
        let layout = try XCTUnwrap(ImageSizing.windowLayout(image: CGSize(width: 100, height: 50), screen: screen, mode: .bestFit))
        XCTAssertEqual(layout.magnification, 1)
    }

    func testScaleToFitEnlargesAndPreservesAspectRatio() throws {
        let layout = try XCTUnwrap(ImageSizing.windowLayout(image: CGSize(width: 100, height: 50), screen: screen, mode: .autoSize))
        XCTAssertEqual(layout.magnification, 9)
        XCTAssertEqual(layout.contentSize, CGSize(width: 900, height: 450))
    }

    func testBothFitModesShrinkLargeImages() throws {
        for mode in [ZoomMode.bestFit, .autoSize] {
            let layout = try XCTUnwrap(ImageSizing.windowLayout(image: CGSize(width: 2000, height: 1000), screen: screen, mode: mode))
            XCTAssertEqual(layout.magnification, 0.45, accuracy: 0.0001)
        }
    }

    func testActualSizeStaysAtOneHundredPercentAndBoundsWindow() throws {
        let layout = try XCTUnwrap(ImageSizing.windowLayout(image: CGSize(width: 3000, height: 2000), screen: screen, mode: .actualSize))
        XCTAssertEqual(layout.magnification, 1)
        XCTAssertEqual(layout.contentSize, CGSize(width: 900, height: 720))
    }

    func testScaleToFitHonorsMaximumZoom() throws {
        let layout = try XCTUnwrap(ImageSizing.windowLayout(image: CGSize(width: 1, height: 1), screen: screen, mode: .autoSize))
        XCTAssertEqual(layout.magnification, 20)
        XCTAssertEqual(layout.contentSize, CGSize(width: 200, height: 150))
    }

    func testInvalidGeometryCannotProduceNaNOrInfiniteZoom() {
        for size in [CGSize.zero, CGSize(width: -1, height: 2), CGSize(width: CGFloat.nan, height: 1), CGSize(width: CGFloat.infinity, height: 1)] {
            XCTAssertNil(ImageSizing.windowLayout(image: size, screen: screen, mode: .autoSize))
            XCTAssertNil(ImageSizing.fitMagnification(image: size, viewport: screen))
        }
        XCTAssertNil(ImageSizing.windowLayout(image: screen, screen: .zero, mode: .autoSize))
    }

    func testVeryLargeImagesCanFitBelowFivePercent() throws {
        let scale = try XCTUnwrap(ImageSizing.fitMagnification(image: CGSize(width: 40_000, height: 10_000), viewport: screen))
        XCTAssertEqual(scale, 0.025, accuracy: 0.000001)
    }

    func testWindowFitEnlargesSmallGIFCanvasWithoutClippingEitherAxis() throws {
        let image = CGSize(width: 330, height: 318)
        for viewport in [CGSize(width: 936, height: 904), CGSize(width: 600, height: 900)] {
            let scale = try XCTUnwrap(ImageSizing.fitMagnification(image: image, viewport: viewport, maximum: 20))
            XCTAssertGreaterThan(scale, 1)
            XCTAssertLessThanOrEqual(image.width * scale, viewport.width + 0.0001)
            XCTAssertLessThanOrEqual(image.height * scale, viewport.height + 0.0001)
            XCTAssertEqual(max(image.width * scale / viewport.width, image.height * scale / viewport.height), 1, accuracy: 0.0001)
        }
    }

    func testWindowFitStillShrinksLargeImagesAndHonorsZoomLimit() throws {
        XCTAssertEqual(try XCTUnwrap(ImageSizing.fitMagnification(image: CGSize(width: 1200, height: 1384),
                                                                 viewport: CGSize(width: 800, height: 600), maximum: 20)),
                       600.0 / 1384.0, accuracy: 0.0001)
        XCTAssertEqual(ImageSizing.fitMagnification(image: CGSize(width: 1, height: 1), viewport: screen, maximum: 20), 20)
    }
}
