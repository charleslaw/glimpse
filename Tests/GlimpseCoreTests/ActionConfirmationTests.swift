import XCTest
@testable import GlimpseCore

final class ActionConfirmationTests: XCTestCase {
    func testMissingFlagConfirmsAndEncodingIncludesFalse() throws {
        let old = try ActionsConfiguration.decode(Data(#"{"version":1,"actions":[]}"#.utf8))
        XCTAssertFalse(old.skipConfirmation)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: old.encoded()) as? [String: Any])
        XCTAssertEqual(encoded["skip_confirmation"] as? Bool, false)
        XCTAssertFalse(ActionsConfiguration.defaults.skipConfirmation)
    }

    func testMissingFlagIsAddedOnLoadAndEditWithoutChangingCustomActions() async throws {
        for edit in [false, true] {
            let folder = try TemporaryFolder()
            let original = Data(#"{"version":1,"actions":[{"label":"Personal","cmd":"open {parentpath}","extra":"keep"}],"personal":42}"#.utf8)
            let url = try folder.file("actions.json", data: original)
            let store = ActionsConfigurationStore(defaultURL: url, preferencesSuite: "GlimpseTests.\(UUID())")
            if edit { _ = try await store.editableURL() } else { _ = try await store.load() }
            let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            XCTAssertEqual(saved["skip_confirmation"] as? Bool, false)
            XCTAssertEqual(saved["personal"] as? Int, 42)
            XCTAssertEqual((saved["actions"] as? [[String: String]])?.first,
                           ["label": "Personal", "cmd": "open {parentpath}", "extra": "keep"])
            let once = try Data(contentsOf: url)
            _ = try await store.load()
            XCTAssertEqual(try Data(contentsOf: url), once)
        }
    }

    func testTrueSurvivesEditingHelpAndReinstallation() async throws {
        let folder = try TemporaryFolder()
        let url = try folder.file("actions.json", data: Data(#"{"version":1,"skip_confirmation":true,"actions":[]}"#.utf8))
        let suite = "GlimpseTests.\(UUID())"
        let store = ActionsConfigurationStore(defaultURL: url, preferencesSuite: suite)
        _ = try await store.editableURL()
        let reinstalled = ActionsConfigurationStore(defaultURL: url, preferencesSuite: suite)
        let config = try await reinstalled.load()
        XCTAssertTrue(config.skipConfirmation)
        XCTAssertTrue(config.actions.isEmpty)
    }

    func testMenuPreferenceUpdatesLatestFileAndPreservesUserFields() async throws {
        let folder = try TemporaryFolder()
        let url = try folder.file("actions.json", data: ActionsConfiguration.defaults.encoded())
        let store = ActionsConfigurationStore(defaultURL: url, preferencesSuite: "GlimpseTests.\(UUID())")
        _ = try await store.load()
        // Simulate an external editor saving between the menu being built and clicked.
        let latest = Data(#"{"version":1,"skip_confirmation":false,"actions":["open {parentpath}"],"personal":{"keep":true}}"#.utf8)
        try latest.write(to: url)
        let off = try await store.setSkipConfirmation(true)
        XCTAssertTrue(off.skipConfirmation)
        XCTAssertEqual(off.actions.first?.command, "open {parentpath}")
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(saved["actions"] as? [String], ["open {parentpath}"])
        XCTAssertEqual((saved["personal"] as? [String: Bool])?["keep"], true)
        let on = try await store.setSkipConfirmation(false)
        XCTAssertFalse(on.skipConfirmation)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testWrongFlagTypesAreRejectedAndKeptForRepair() async throws {
        for flag in ["null", "1", "0", #""true""#, "[]", "{}"] {
            let folder = try TemporaryFolder()
            let data = Data("{\"version\":1,\"actions\":[],\"skip_confirmation\":\(flag)}".utf8)
            let url = try folder.file("actions.json", data: data)
            let store = ActionsConfigurationStore(defaultURL: url, preferencesSuite: "GlimpseTests.\(UUID())")
            do { _ = try await store.load(); XCTFail("Invalid flag accepted: \(flag)") }
            catch { XCTAssertTrue(error.localizedDescription.contains("skip_confirmation"), error.localizedDescription) }
            _ = try await store.editableURL()
            do { _ = try await store.setSkipConfirmation(true); XCTFail("Invalid config overwritten") } catch {}
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }

    func testResetRestoresConfirmationAndDefaultActions() async throws {
        let folder = try TemporaryFolder()
        let url = try folder.file("actions.json", data: ActionsConfiguration(actions: [], skipConfirmation: true).encoded())
        let store = ActionsConfigurationStore(defaultURL: url, preferencesSuite: "GlimpseTests.\(UUID())")
        try Data().write(to: url)
        let reset = try await store.load()
        XCTAssertFalse(reset.skipConfirmation)
        XCTAssertEqual(reset.actions, ActionsConfiguration.defaults.actions)
    }
}
