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
}
