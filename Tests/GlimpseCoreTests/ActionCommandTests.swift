import XCTest
@testable import GlimpseCore

final class ActionCommandTests: XCTestCase {
    func testStringsAndLabelCommandObjectsMixWithExistingActions() throws {
        let json = #"{"version":1,"actions":["chrome {fname}",{"label":"Open dir","cmd":"open {ppath}"},{"id":"copy","title":"Copy","kind":"copyImagePath"}]}"#
        let config = try ActionsConfiguration.decode(Data(json.utf8))
        XCTAssertEqual(config.actions.map(\.title), ["chrome {fname}", "Open dir", "Copy"])
        XCTAssertEqual(config.actions.map(\.kind), [.runCommand, .runCommand, .copyImagePath])
        XCTAssertEqual(Set(config.actions.map(\.id)).count, 3)
        XCTAssertEqual(try ActionsConfiguration.decode(config.encoded()), config)
    }

    func testQuotesEscapesAndEmptyArgumentsAreTokenizedWithoutAShell() throws {
        let command = try ActionCommand.parse(#"tool "two words" 'literal text' escaped\ space "" "a\"b""#)
        XCTAssertEqual(command.executable, "tool")
        XCTAssertEqual(command.arguments, ["two words", "literal text", "escaped space", "", "a\"b"])
        let operators = try ActionCommand.parse("tool ; | & $(whoami)")
        XCTAssertEqual(operators.arguments, [";", "|", "&", "$(whoami)"])
    }

    func testSubstitutionCannotIntroduceArgumentsOrExpandFilenameTokensAgain() throws {
        let file = URL(fileURLWithPath: "/tmp/folder with spaces/a '{ppath}' $(touch unsafe).png")
        let command = try ActionCommand.parse(#"tool {fname} "{filepath}" {ppath} "--name={filename}" {fpath}"#)
        XCTAssertEqual(command.expandedArguments(for: file), [file.lastPathComponent, file.path,
                       file.deletingLastPathComponent().path, "--name=" + file.lastPathComponent, file.path])
    }

    func testNewURLAliasesArePercentEncoded() throws {
        let action = ImageAction(id: "url", title: "URL", kind: .openURL,
                                 url: "https://example.com/?name={fname}&parent={ppath}")
        _ = try ActionsConfiguration(actions: [action]).encoded()
        let file = URL(fileURLWithPath: "/tmp/folder&other=1/photo#name.png")
        let url = try XCTUnwrap(action.expandedURL(for: file))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.map(\.value), [file.lastPathComponent, file.deletingLastPathComponent().path])
    }

    func testRejectsUnclosedQuotesEscapesEmptyAndOversizedCommands() {
        for command in ["", "   ", "tool 'unfinished", "tool \\", String(repeating: "a", count: 8_193),
                        "tool \0", "tool " + Array(repeating: "arg", count: 33).joined(separator: " ")] {
            XCTAssertThrowsError(try ActionCommand.parse(command), command)
        }
    }

    func testCommandsRejectAmbiguityUnknownTokensAndInlineInterpreters() {
        let invalid = [
            #"{"label":"A","cmd":"open {unknown}"}"#,
            #"{"label":"A","cmd":"../open {fname}"}"#,
            #"{"label":"A","cmd":"{fname} x"}"#,
            #"{"label":"A","cmd":"sh -c 'echo {fname}'"}"#,
            #"{"label":"A","cmd":"open {fname}","arguments":[]}"#,
            #"{"label":"A","cmd":"open {fname}","kind":"copyImagePath"}"#,
        ]
        for action in invalid {
            XCTAssertThrowsError(try ActionsConfiguration.decode(Data("{\"version\":1,\"actions\":[\(action)]}".utf8)))
        }
    }

    func testExecutableResolutionUsesSpecifiedDirectoriesAndResolvesSymlinks() throws {
        let folder = try TemporaryFolder()
        let executable = try folder.file("my-viewer", data: Data("#!/bin/sh\nexit 0\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let command = try ActionCommand.parse("my-viewer {fname}")
        XCTAssertThrowsError(try command.resolved(searchDirectories: []))
        XCTAssertEqual(try command.resolved(searchDirectories: [folder.url]).executable, executable.resolvingSymlinksInPath().path)
        let alias = folder.url.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: executable)
        XCTAssertEqual(try ActionCommand(executable: alias.path, arguments: []).resolved().executable,
                       executable.resolvingSymlinksInPath().path)
    }

    func testChromeUsesNativeAppOpeningRatherThanATimedBrowserProcess() throws {
        let command = try ActionCommand.parse("chrome {fname}").resolved()
        XCTAssertEqual(command.executable, "/usr/bin/open")
        XCTAssertEqual(command.arguments, ["-b", "com.google.Chrome", "--", "{fname}"])
    }

    func testOpeningConfigRepairsNotesWithoutChangingCommandSyntaxOrOtherFields() async throws {
        let folder = try TemporaryFolder()
        let url = try folder.file("actions.json", data: Data(#"{"version":1,"notes":"changed","actions":["chrome {fname}",{"label":"Open dir","cmd":"open {ppath}"}],"personal":{"keep":true}}"#.utf8))
        let store = ActionsConfigurationStore(defaultURL: url, preferencesSuite: "GlimpseTests.\(UUID())")
        _ = try await store.editableURL()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(object["notes"] as? String, ActionsConfiguration.requiredNotes)
        XCTAssertEqual(object["variables"] as? [String: String], ActionsConfiguration.standardVariables)
        XCTAssertEqual(object["examples"] as? [String: String], ActionsConfiguration.standardExamples)
        let actions = try XCTUnwrap(object["actions"] as? [Any])
        XCTAssertEqual(actions[0] as? String, "chrome {fname}")
        XCTAssertEqual(actions[1] as? [String: String], ["label": "Open dir", "cmd": "open {ppath}"])
        XCTAssertEqual((object["personal"] as? [String: Bool])?["keep"], true)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let once = try Data(contentsOf: url)
        _ = try await store.editableURL()
        XCTAssertEqual(try Data(contentsOf: url), once)
    }

    func testOpeningOldConfigInsertsMissingNoteAndPreservesActionsAcrossStoreInstances() async throws {
        let folder = try TemporaryFolder()
        let url = try folder.file("actions.json", data: Data(#"{"version":1,"actions":[{"label":"Open dir","cmd":"open {ppath}"}]}"#.utf8))
        let suite = "GlimpseTests.\(UUID())"
        let first = ActionsConfigurationStore(defaultURL: url, preferencesSuite: suite)
        _ = try await first.editableURL()
        let saved = try Data(contentsOf: url)
        let reinstalled = ActionsConfigurationStore(defaultURL: url, preferencesSuite: suite)
        let config = try await reinstalled.load()
        XCTAssertEqual(config.actions.first?.command, "open {ppath}")
        XCTAssertEqual(config.notes, ActionsConfiguration.requiredNotes)
        XCTAssertEqual(try Data(contentsOf: url), saved)
    }

    func testDefaultsDocumentAllVariablesAndGoogleLensExampleWithoutAddingActions() throws {
        let config = try ActionsConfiguration.decode(ActionsConfiguration.defaults.encoded())
        XCTAssertEqual(Set(config.variables?.keys.map { $0 } ?? []), Set(ActionPlaceholders.names.map { "{\($0)}" }))
        XCTAssertEqual(config.examples?["Google image search"], "google-lens {filepath}")
        XCTAssertEqual(config.actions.count, 2)
    }

    func testGoogleLensHelperOnlyAcceptsSelectedImageTokens() throws {
        for argument in ["", " {filepath}", " {fname}"] {
            let action = ImageAction(id: "lens", title: "Lens", kind: .runCommand, command: "google-lens" + argument)
            XCTAssertNoThrow(try ActionsConfiguration(actions: [action]).encoded())
        }
        for argument in [" {ppath}", " /other/private/file.png", " {fpath} extra"] {
            let action = ImageAction(id: "lens", title: "Lens", kind: .runCommand, command: "google-lens" + argument)
            XCTAssertThrowsError(try ActionsConfiguration(actions: [action]).encoded())
        }
    }

    func testBadConfigErrorsExplainWhereToFixTheFile() {
        for (json, hint) in [("{bad json", "JSON"),
                             (#"{"version":1}"#, "actions"),
                             (#"{"version":1,"actions":[{"label":"Open","cmd":123}]}"#, "config.actions[0].cmd")] {
            do { _ = try ActionsConfiguration.decode(Data(json.utf8)); XCTFail("Invalid config was accepted") }
            catch { XCTAssertTrue(error.localizedDescription.contains(hint), error.localizedDescription) }
        }
    }
}
