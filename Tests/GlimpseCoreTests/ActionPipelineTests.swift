import XCTest
@testable import GlimpseCore

final class ActionPipelineTests: XCTestCase {
    func testPipesSplitOnlyOutsideQuotesAndEscapes() throws {
        let pipeline = try ActionPipeline.parse(#"printf '%s' "a|b" \| | cat|cat"#)
        XCTAssertEqual(pipeline.stages.map(\.executable), ["printf", "cat", "cat"])
        XCTAssertEqual(pipeline.stages[0].arguments, ["%s", "a|b", "|"])
        XCTAssertThrowsError(try ActionCommand.parse("echo hi | cat"))
    }

    func testRejectsEmptyStagesAndTooManyStages() {
        for command in ["|cat", "cat|", "echo hi || cat", "cat|cat|cat|cat|cat"] {
            XCTAssertThrowsError(try ActionPipeline.parse(command), command)
        }
    }

    func testEachStageIsValidatedAndLensCannotBePiped() {
        for command in ["echo hi | sh -c 'touch unsafe'", "echo hi | cat {unknown}",
                        "echo hi | ../cat", "echo hi | google-lens {filepath}",
                        "google-lens {filepath} | cat"] {
            let action = ImageAction(id: "a", title: "A", kind: .runCommand, command: command)
            XCTAssertThrowsError(try ActionsConfiguration(actions: [action]).encoded(), command)
        }
    }

    func testFilenameCannotAddPipelineStagesOrCommands() throws {
        let file = URL(fileURLWithPath: "/tmp/a 'quote' \"double\" | $(touch unsafe); {filename}.png")
        let pipeline = try ActionPipeline.parse(#"echo "{filepath}" | pbcopy"#)
        XCTAssertEqual(pipeline.stages.count, 2)
        XCTAssertEqual(pipeline.stages[0].expandedArguments(for: file), [file.path])
    }

    func testDefaultsAndDocumentationExamplesEncodeOnlyLabelAndCommand() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: ActionsConfiguration.defaults.encoded()) as? [String: Any])
        for key in ["actions", "examples"] {
            let actions = try XCTUnwrap(object[key] as? [[String: String]])
            XCTAssertFalse(actions.isEmpty)
            for action in actions { XCTAssertEqual(Set(action.keys), ["label", "cmd"]) }
        }
        XCTAssertEqual(Set(ActionsConfiguration.standardVariables.keys), ["{filename}", "{filepath}", "{parentpath}"])
        for token in ["{fname}", "{fpath}", "{ppath}"] { XCTAssertThrowsError(try ActionPlaceholders.validate(token)) }
    }

    func testOldDefaultsAndAbbreviationsMigrateWithoutLosingCustomFields() async throws {
        let folder = try TemporaryFolder()
        let json = #"{"version":1,"actions":[{"id":"copy","kind":"copyImagePath","title":"Copy"},{"id":"open","kind":"openImageLocation","title":"Folder"},{"label":"Custom","cmd":"open {ppath}","personal":true},"chrome {fname}",{"id":"script","kind":"runCommand","title":"Script","executable":"/bin/cat","arguments":["{fpath}"]}],"examples":{"Old":"open {ppath}"},"personal":{"keep":true}}"#
        let url = try folder.file("actions.json", data: Data(json.utf8))
        let store = ActionsConfigurationStore(defaultURL: url, preferencesSuite: "GlimpseTests.\(UUID())")
        let config = try await store.load()
        XCTAssertEqual(config.actions.map(\.command), [#"echo "{filepath}" | pbcopy"#, "open {parentpath}", "open {parentpath}", "chrome {filename}", nil])
        XCTAssertEqual(config.actions.last?.arguments, ["{filepath}"])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let actions = try XCTUnwrap(object["actions"] as? [Any])
        XCTAssertEqual(actions[0] as? [String: String], ["label": "Copy", "cmd": #"echo "{filepath}" | pbcopy"#])
        XCTAssertEqual((actions[2] as? [String: Any])?["personal"] as? Bool, true)
        XCTAssertEqual((object["personal"] as? [String: Bool])?["keep"], true)
        XCTAssertEqual((object["examples"] as? [[String: String]])?.count, 3)
        let migrated = try Data(contentsOf: url)
        _ = try await store.load()
        XCTAssertEqual(try Data(contentsOf: url), migrated)
    }

    func testInvalidSchemaIsNotPartiallyMigrated() async throws {
        let folder = try TemporaryFolder()
        let original = Data(#"{"version":1,"actions":[{"kind":"copyImagePath","title":"Copy"},{"label":"Bad","cmd":"open {unknown}"}]}"#.utf8)
        let url = try folder.file("actions.json", data: original)
        let store = ActionsConfigurationStore(defaultURL: url, preferencesSuite: "GlimpseTests.\(UUID())")
        do { _ = try await store.load(); XCTFail("Bad config accepted") } catch {}
        _ = try await store.editableURL()
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}
