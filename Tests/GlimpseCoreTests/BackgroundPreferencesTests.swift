import XCTest
@testable import GlimpseCore

final class BackgroundPreferencesTests: XCTestCase {
    func testNewAndUnknownPreferencesUsePattern() throws {
        try withDefaults { defaults in
            XCTAssertEqual(BackgroundPreferences(defaults: defaults).style, .checkerboard)
            defaults.set("unknown", forKey: "backgroundStyle")
            XCTAssertEqual(BackgroundPreferences(defaults: defaults).style, .checkerboard)
        }
    }

    func testChoiceAndCustomRGBSurviveReopeningAndSwitchingPresets() throws {
        try withDefaults { defaults in
            let saved = try XCTUnwrap(BackgroundRGBColor(red: 12, green: 34, blue: 255))
            let preferences = BackgroundPreferences(defaults: defaults)
            preferences.customColor = saved
            for style in ViewerBackgroundStyle.allCases {
                preferences.style = style
                let reopened = BackgroundPreferences(defaults: defaults)
                XCTAssertEqual(reopened.style, style)
                XCTAssertEqual(reopened.customColor, saved)
            }
        }
    }

    func testInvalidRGBDefaultsFallBackSafely() throws {
        try withDefaults { defaults in
            let malformedValues: [Any] = [[1, 2], [1, 2, 256], [-1, 2, 3], ["red", "green", "blue"], "bad"]
            for malformed in malformedValues {
                defaults.set(malformed, forKey: "backgroundRGB")
                XCTAssertEqual(BackgroundPreferences(defaults: defaults).customColor, .veryDarkGray)
            }
        }
    }

    func testRGBValidatesAllComponentsIncludingBoundaries() {
        XCTAssertEqual(BackgroundRGBColor(red: 0, green: 0, blue: 0), .black)
        XCTAssertEqual(BackgroundRGBColor(red: 255, green: 255, blue: 255), .white)
        XCTAssertNil(BackgroundRGBColor(red: -1, green: 0, blue: 0))
        XCTAssertNil(BackgroundRGBColor(red: 0, green: 256, blue: 0))
        XCTAssertNil(BackgroundRGBColor(red: 0, green: 0, blue: Int.max))
    }

    private func withDefaults(_ check: (UserDefaults) throws -> Void) throws {
        let suite = "GlimpseTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try check(defaults)
    }
}
