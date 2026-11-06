import XCTest
@testable import GlimpseCore

final class ProcessPipelineTests: XCTestCase {
    @MainActor func testLiteralFilenamePassesThroughRealPipeline() async throws {
        let folder = try TemporaryFolder()
        let outputURL = try folder.file("output", data: Data())
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        let text = "/tmp/a 'quote' \"double\" | $(touch unsafe); {filepath}.png"
        let complete = expectation(description: "pipeline completed")
        let pipeline = ProcessPipeline(commands: [ActionCommand(executable: "/usr/bin/printf", arguments: ["%s", text]),
                                                  ActionCommand(executable: "/bin/cat", arguments: [])],
                                       directory: folder.url, output: output) { statuses in
            XCTAssertEqual(statuses, [0, 0]); complete.fulfill()
        }
        try pipeline.start()
        await fulfillment(of: [complete], timeout: 5)
        XCTAssertEqual(try String(contentsOf: outputURL, encoding: .utf8), text)
        XCTAssertFalse(pipeline.isRunning)
        XCTAssertThrowsError(try pipeline.start())
    }

    @MainActor func testLargePipelineDrainsAndReceivesEOF() async throws {
        let folder = try TemporaryFolder()
        let data = Data(repeating: 65, count: 300_000)
        let input = try folder.file("input", data: data)
        let outputURL = try folder.file("output", data: Data())
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        let complete = expectation(description: "large pipeline completed")
        let pipeline = ProcessPipeline(commands: [ActionCommand(executable: "/bin/cat", arguments: [input.path]),
                                                  ActionCommand(executable: "/usr/bin/tr", arguments: ["A", "B"]),
                                                  ActionCommand(executable: "/bin/cat", arguments: [])],
                                       directory: folder.url, output: output) { statuses in
            XCTAssertEqual(statuses, [0, 0, 0]); complete.fulfill()
        }
        try pipeline.start()
        await fulfillment(of: [complete], timeout: 5)
        XCTAssertEqual(try Data(contentsOf: outputURL), Data(repeating: 66, count: data.count))
    }

    @MainActor func testPartialLaunchFailureCleansUpStartedConsumer() async throws {
        let folder = try TemporaryFolder()
        let pipeline = ProcessPipeline(commands: [ActionCommand(executable: "/nonexistent/glimpse-command", arguments: []),
                                                  ActionCommand(executable: "/bin/cat", arguments: [])], directory: folder.url) { _ in
            XCTFail("A failed startup must not complete normally")
        }
        XCTAssertThrowsError(try pipeline.start())
        for _ in 0..<100 where pipeline.isRunning { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(pipeline.isRunning)
    }

    @MainActor func testTimeoutTerminatesEveryStageAndReportsFailure() async throws {
        let folder = try TemporaryFolder()
        let complete = expectation(description: "timed out pipeline completed")
        let pipeline = ProcessPipeline(commands: [ActionCommand(executable: "/bin/sleep", arguments: ["5"]),
                                                  ActionCommand(executable: "/bin/cat", arguments: [])],
                                       directory: folder.url, timeoutNanoseconds: 50_000_000) { statuses in
            XCTAssertEqual(statuses.count, 2)
            XCTAssertTrue(statuses.contains { $0 != 0 }); complete.fulfill()
        }
        try pipeline.start()
        await fulfillment(of: [complete], timeout: 5)
        XCTAssertFalse(pipeline.isRunning)
    }

    @MainActor func testCancellationCleansUpWithoutCompletionCallback() async throws {
        let folder = try TemporaryFolder()
        let pipeline = ProcessPipeline(commands: [ActionCommand(executable: "/bin/sleep", arguments: ["5"])], directory: folder.url) { _ in
            XCTFail("Cancelled action should not show an exit alert")
        }
        try pipeline.start()
        pipeline.cancel()
        for _ in 0..<100 where pipeline.isRunning { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(pipeline.isRunning)
    }
}
