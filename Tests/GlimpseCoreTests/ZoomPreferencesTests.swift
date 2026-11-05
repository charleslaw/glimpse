import XCTest
@testable import GlimpseCore

final class ZoomPreferencesTests: XCTestCase {
    func testModeSurvivesRecreatingThePreferencesStore() throws {
        let suite = "GlimpseTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ZoomPreferences(defaults: defaults)
        for mode in ZoomMode.allCases {
            preferences.mode = mode
            XCTAssertEqual(ZoomPreferences(defaults: defaults).mode, mode)
        }
    }

    func testOldAutoSizePreferenceStillSelectsScaleToFit() throws {
        let suite = "GlimpseTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("autoSize", forKey: "zoomMode")
        XCTAssertEqual(ZoomPreferences(defaults: defaults).mode.menuTitle, "Scale to Fit")
    }

    func testMissingAndInvalidPreferencesFallBackSafely() throws {
        let suite = "GlimpseTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ZoomPreferences(defaults: defaults)
        XCTAssertEqual(preferences.mode, .bestFit)
        defaults.set("unknown-mode", forKey: "zoomMode")
        XCTAssertEqual(preferences.mode, .bestFit)
    }
}
