import XCTest
@testable import GlimpseCore

final class ActionsConfigurationTests: XCTestCase {
    func testDefaultsRoundTripAndContainTheTwoRequestedActions() throws {
        let value = try ActionsConfiguration.decode(ActionsConfiguration.defaults.encoded())
        XCTAssertEqual(value.actions.map(\.kind), [.copyImagePath, .openImageLocation])
        XCTAssertEqual(value.notes, "To reset the actions, save a blank file and Glimpse will regenerate the defaults.")
    }

    func testBlankAndWhitespaceOnlyFilesRegenerateDefaultsIncludingNotes() async throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("actions.json")
        let store = ActionsConfigurationStore(defaultURL: url, preferencesSuite: "GlimpseTests.\(UUID())")
        for text in ["", " \n\t\r", "\u{feff} \n", "\u{2003}\n"] {
            try Data(text.utf8).write(to: url)
            let restored = try await store.load()
            XCTAssertEqual(restored, .defaults)
            XCTAssertEqual(try ActionsConfiguration.decode(Data(contentsOf: url)), .defaults)
        }
    }

    func testExplicitEmptyActionsArePreservedByLoading() async throws {
        let folder = try TemporaryFolder()
        let original = Data("{\"version\":1,\"actions\":[]}".utf8)
        let url = try folder.file("actions.json", data: original)
        let store = ActionsConfigurationStore(defaultURL: url, preferencesSuite: "GlimpseTests.\(UUID())")
        let config = try await store.load()
        XCTAssertTrue(config.actions.isEmpty)
        XCTAssertNil(config.notes)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testCustomNotesRoundTripAndOlderFilesRemainValid() throws {
        let config = ActionsConfiguration(actions: [], notes: "Personal commands")
        XCTAssertEqual(try ActionsConfiguration.decode(config.encoded()), config)
        let old = try ActionsConfiguration.decode(Data("{\"version\":1,\"actions\":[]}".utf8))
        XCTAssertNil(old.notes)
        XCTAssertThrowsError(try ActionsConfiguration(actions: [], notes: String(repeating: "a", count: 8_193)).encoded())
    }

    func testPreviouslySelectedConfigAlsoRegeneratesWhenCleared() async throws {
        let folder = try TemporaryFolder()
        let url = try folder.file("chosen.json", data: ActionsConfiguration.defaults.encoded())
        let store = ActionsConfigurationStore(defaultURL: folder.url.appendingPathComponent("default.json"),
                                              preferencesSuite: "GlimpseTests.\(UUID())")
        try await store.choose(url)
        try Data().write(to: url)
        let restored = try await store.load()
        XCTAssertEqual(restored, .defaults)
        XCTAssertEqual(try ActionsConfiguration.decode(Data(contentsOf: url)), .defaults)
    }

    func testEmptyActionsAreValidSoManagementCanRemainAvailable() throws {
        XCTAssertTrue(try ActionsConfiguration.decode(Data("{\"version\":1,\"actions\":[]}".utf8)).actions.isEmpty)
    }

    func testArgumentsPreserveSpacesQuotesAndShellMetacharactersAsData() {
        let action = ImageAction(id: "print", title: "Print", kind: .runCommand,
                                 executable: "/usr/bin/lp", arguments: ["--", "{filepath}", "{filename}"])
        let file = URL(fileURLWithPath: "/tmp/a b;$(touch unsafe)'\".png")
        XCTAssertEqual(action.expandedArguments(for: file), ["--", file.path, file.lastPathComponent])
    }

    func testPlaceholderTextInsideFileNamesIsNotExpandedAgain() {
        let file = URL(fileURLWithPath: "/tmp/{filepath}.jpg")
        let action = ImageAction(id: "test", title: "Test", kind: .runCommand,
                                 executable: "/usr/bin/printf", arguments: ["{filename}", "{filepath}"])
        XCTAssertEqual(action.expandedArguments(for: file), ["{filepath}.jpg", file.path])
    }

    func testURLPlaceholderCannotInjectAnotherQueryParameter() throws {
        let action = ImageAction(id: "search", title: "Search", kind: .openURL,
                                 url: "https://example.com/search?q={filename}")
        let file = URL(fileURLWithPath: "/tmp/photo&a=b#c.jpg")
        let url = try XCTUnwrap(action.expandedURL(for: file))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.value, file.lastPathComponent)
    }

    func testRejectsInvalidKindsVersionsDuplicateIDsAndUnknownTokens() {
        for json in [
            "{\"version\":2,\"actions\":[]}",
            "{\"version\":1,\"actions\":[{\"id\":\"a\",\"title\":\"A\",\"kind\":\"unknown\"}]}",
            "{\"version\":1,\"actions\":[{\"id\":\"a\",\"title\":\"A\",\"kind\":\"copyImagePath\"},{\"id\":\"a\",\"title\":\"A\",\"kind\":\"copyImagePath\"}]}"
        ] { XCTAssertThrowsError(try ActionsConfiguration.decode(Data(json.utf8))) }
        let action = ImageAction(id: "a", title: "A", kind: .runCommand, executable: "/usr/bin/lp", arguments: ["{unknown}"])
        XCTAssertThrowsError(try ActionsConfiguration(actions: [action]).encoded())
    }

    func testRejectsRelativeExecutablesAndNonHTTPSURLs() {
        for action in [
            ImageAction(id: "a", title: "A", kind: .runCommand, executable: "lp"),
            ImageAction(id: "a", title: "A", kind: .runCommand, executable: "/tmp/{filename}"),
            ImageAction(id: "a", title: "A", kind: .openURL, url: "file:///etc/passwd"),
            ImageAction(id: "a", title: "A", kind: .openURL, url: "https://user:secret@example.com"),
            ImageAction(id: "a", title: "A", kind: .openURL, url: "https://{filename}/")
        ] { XCTAssertThrowsError(try ActionsConfiguration(actions: [action]).encoded()) }
    }

    func testRejectsOversizedConfigurations() {
        XCTAssertThrowsError(try ActionsConfiguration.decode(Data(repeating: 32, count: 65_537)))
    }

    func testRejectsControlCharactersAndOversizedUnicodeLabels() {
        for title in ["Hidden\0Action", String(repeating: "a\u{301}", count: 81)] {
            XCTAssertThrowsError(try ActionsConfiguration(actions: [ImageAction(id: "a", title: title, kind: .copyImagePath)]).encoded())
        }
    }

    func testInlineInterpretersCannotTurnFileNamesIntoCode() {
        for (executable, arguments) in [
            ("/bin/sh", ["-c", "echo {filename}"]),
            ("/bin/zsh", ["-lc", "echo {filepath}"]),
            ("/usr/bin/python3", ["-c", "print('{filename}')"]),
            ("/usr/bin/env", ["-S", "python3 -c {filename}"])
        ] {
            let action = ImageAction(id: "a", title: "A", kind: .runCommand, executable: executable, arguments: arguments)
            XCTAssertThrowsError(try ActionsConfiguration(actions: [action]).encoded())
        }
    }

    func testTrustedScriptCanReceiveASeparateFileArgument() throws {
        let action = ImageAction(id: "a", title: "A", kind: .runCommand,
                                 executable: "/usr/bin/python3", arguments: ["/Users/me/action.py", "{filepath}"])
        XCTAssertNoThrow(try ActionsConfiguration(actions: [action]).encoded())
    }

    func testOversizedInvalidConfigCanBeResetWithoutLosingItsBackup() async throws {
        let folder = try TemporaryFolder()
        let original = Data(repeating: 65, count: 100_000)
        let url = try folder.file("actions.json", data: original)
        let store = ActionsConfigurationStore(defaultURL: url, preferencesSuite: "GlimpseTests.\(UUID())")
        let backupValue = try await store.reset()
        let backup = try XCTUnwrap(backupValue)
        XCTAssertEqual(try Data(contentsOf: backup), original)
        let reset = try await store.load()
        XCTAssertEqual(reset, .defaults)
    }

    func testStoreCreatesDefaultsAndResetBacksUpEdits() async throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("actions.json")
        let store = ActionsConfigurationStore(defaultURL: url, preferencesSuite: "GlimpseTests.\(UUID())")
        let defaults = try await store.load()
        XCTAssertEqual(defaults, .defaults)
        let edited = try ActionsConfiguration(actions: []).encoded()
        try edited.write(to: url)
        let savedBackup = try await store.reset()
        let backup = try XCTUnwrap(savedBackup)
        XCTAssertEqual(try Data(contentsOf: backup), edited)
        let reset = try await store.load()
        XCTAssertEqual(reset, .defaults)
    }

    func testInvalidConfigIsNeverOverwrittenByLoading() async throws {
        let folder = try TemporaryFolder()
        let data = Data("invalid json".utf8)
        let url = try folder.file("actions.json", data: data)
        let store = ActionsConfigurationStore(defaultURL: url, preferencesSuite: "GlimpseTests.\(UUID())")
        do { _ = try await store.load(); XCTFail("Invalid config accepted") } catch {}
        XCTAssertEqual(try Data(contentsOf: url), data)
        let editable = try await store.editableURL()
        XCTAssertEqual(editable, url)
    }

    func testChosenConfigPathPersistsAndInvalidChoiceDoesNotReplaceIt() async throws {
        let folder = try TemporaryFolder()
        let suite = "GlimpseTests.\(UUID())"
        let defaultURL = folder.url.appendingPathComponent("default.json")
        let chosen = try folder.file("chosen.json", data: ActionsConfiguration.defaults.encoded())
        let bad = try folder.file("invalid.json", data: Data("bad".utf8))
        let store = ActionsConfigurationStore(defaultURL: defaultURL, preferencesSuite: suite)
        try await store.choose(chosen)
        do { try await store.choose(bad); XCTFail("Invalid choice accepted") } catch {}
        let recreated = ActionsConfigurationStore(defaultURL: defaultURL, preferencesSuite: suite)
        let selected = await recreated.fileURL
        XCTAssertEqual(selected, chosen)
    }
}
