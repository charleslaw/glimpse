import XCTest
@testable import GlimpseCore

final class ActionsBackupTests: XCTestCase {
    private func backups(_ folder: TemporaryFolder) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder.url, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("-backup-") }
    }

    func testOpeningUnchangedConfigBacksUpLastGoodContentsBeforeAnAccidentalBlankSave() async throws {
        let folder = try TemporaryFolder()
        let original = try ActionsConfiguration(actions: [ImageAction.configured(label: "Personal", cmd: "open {parentpath}", index: 0)],
                                                 notes: ActionsConfiguration.requiredNotes,
                                                 variables: ActionsConfiguration.standardVariables,
                                                 examples: ActionsConfiguration.standardExamples).encoded()
        let url = try folder.file("actions.json", data: original)
        let store = ActionsConfigurationStore(defaultURL: url, preferencesSuite: "GlimpseTests.\(UUID())")
        _ = try await store.editableURL()
        let goodBackup = try XCTUnwrap(backups(folder).first)
        XCTAssertEqual(try Data(contentsOf: goodBackup), original)
        try Data().write(to: url)
        let reset = try await store.load()
        XCTAssertEqual(reset, .defaults)
        XCTAssertEqual(try backups(folder).count, 2)
        XCTAssertEqual(try Data(contentsOf: goodBackup), original)
    }

    func testEveryAppRewriteBacksUpOriginalAndUnchangedLoadsDoNotCreateDuplicates() async throws {
        let folder = try TemporaryFolder()
        let original = Data(#"{"version":1,"actions":["open {ppath}"],"personal":true}"#.utf8)
        let url = try folder.file("actions.json", data: original)
        let store = ActionsConfigurationStore(defaultURL: url, preferencesSuite: "GlimpseTests.\(UUID())")
        _ = try await store.load()
        XCTAssertEqual(try backups(folder).count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups(folder).first)), original)
        let migrated = try Data(contentsOf: url)
        _ = try await store.load()
        XCTAssertEqual(try backups(folder).count, 1)
        _ = try await store.setSkipConfirmation(true)
        let all = try backups(folder)
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(try all.contains { try Data(contentsOf: $0) == migrated })
        for file in all + [url] {
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }

    func testRecoveryWarningNamesExactBackupAndSurvivesHelpAndPreferenceChanges() async throws {
        let folder = try TemporaryFolder()
        let original = Data(#"{"version":1,"actions":["open {filepath}","#.utf8)
        let url = try folder.file("config.json", data: original)
        let store = ActionsConfigurationStore(defaultURL: url, preferencesSuite: "GlimpseTests.\(UUID())")
        let restored = try await store.load()
        let backup = try XCTUnwrap(backups(folder).first)
        let warning = try XCTUnwrap(restored.warning)
        let path = try XCTUnwrap(warning.components(separatedBy: "was saved in ").last?.components(separatedBy: ". To restore it").first)
        XCTAssertEqual(URL(fileURLWithPath: path).resolvingSymlinksInPath(), backup.resolvingSymlinksInPath())
        XCTAssertTrue(warning.contains("copy and paste"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(json["WARNING"] as? String, warning)
        XCTAssertEqual(try Data(contentsOf: backup), original)
        _ = try await store.editableURL()
        let edited = try await store.setSkipConfirmation(true)
        XCTAssertEqual(edited.warning, warning)
        XCTAssertEqual(try ActionsConfiguration.decode(edited.encoded()).warning, warning)
        let once = try backups(folder).count
        _ = try await store.load()
        XCTAssertEqual(try backups(folder).count, once)
    }

    func testRepeatedInvalidSavesGetUniqueBackupsAndKeepEarlierOnes() async throws {
        let folder = try TemporaryFolder()
        let url = try folder.file("actions.json", data: Data("first invalid".utf8))
        let store = ActionsConfigurationStore(defaultURL: url, preferencesSuite: "GlimpseTests.\(UUID())")
        let first = try await store.load()
        try Data("second invalid".utf8).write(to: url)
        let second = try await store.load()
        XCTAssertNotEqual(first.warning, second.warning)
        let files = try backups(folder)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(Set(try files.map { try String(contentsOf: $0, encoding: .utf8) }), ["first invalid", "second invalid"])
    }

    func testOversizedAndNonUTF8FilesRecoverWithoutLosingAnyBytes() async throws {
        for original in [Data(repeating: 65, count: 100_000), Data([0xff, 0x00, 0xfe, 0x7f])] {
            let folder = try TemporaryFolder()
            let url = try folder.file("actions.json", data: original)
            let store = ActionsConfigurationStore(defaultURL: url, preferencesSuite: "GlimpseTests.\(UUID())")
            let config = try await store.load()
            XCTAssertNotNil(config.warning)
            XCTAssertFalse(config.skipConfirmation)
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups(folder).first)), original)
        }
    }

    func testNonregularPathsAndSymlinksAreNeverReplaced() async throws {
        let folder = try TemporaryFolder()
        let directory = folder.url.appendingPathComponent("directory.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let original = try folder.file("original", data: Data("bad json".utf8))
        let link = folder.url.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        for url in [directory, link] {
            let store = ActionsConfigurationStore(defaultURL: url, preferencesSuite: "GlimpseTests.\(UUID())")
            do { _ = try await store.load(); XCTFail("Unsafe path replaced") } catch {}
            do { _ = try await store.editableURL(); XCTFail("Unsafe path opened") } catch {}
        }
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), original.path)
        XCTAssertEqual(try Data(contentsOf: original), Data("bad json".utf8))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType, .typeDirectory)
        XCTAssertTrue(try backups(folder).isEmpty)
    }

    func testFailedPreparationLeavesOriginalFileUntouched() async throws {
        let folder = try TemporaryFolder()
        let original = Data("bad json".utf8)
        let url = try folder.file("actions.json", data: original)
        let store = ActionsConfigurationStore(defaultURL: url, preferencesSuite: "GlimpseTests.\(UUID())")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.url.path) }
        do { _ = try await store.load(); XCTFail("A failed backup must not replace the original") } catch {}
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertTrue(try backups(folder).isEmpty)
    }
}
