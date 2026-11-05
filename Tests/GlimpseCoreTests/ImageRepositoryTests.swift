import AppKit
import XCTest
@testable import GlimpseCore

// The lock protects the observations shared between the actor and test executor.
private final class DecoderProbe: ImageDecoding, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var ranOnMain = false

    var observations: (Int, Bool) {
        lock.lock(); defer { lock.unlock() }
        return (calls, ranOnMain)
    }

    func decode(_ url: URL) throws -> NSImage {
        lock.lock()
        calls += 1
        ranOnMain = Thread.isMainThread
        lock.unlock()
        return NSImage(size: NSSize(width: 2, height: 2))
    }
}

final class ImageRepositoryTests: XCTestCase {
    @MainActor func testDecodingIsOffTheMainThread() async throws {
        let probe = DecoderProbe()
        let repository = ImageRepository(decoder: probe)
        _ = try await repository.load(URL(fileURLWithPath: "/test.jpg"))
        XCTAssertEqual(probe.observations.0, 1)
        XCTAssertFalse(probe.observations.1)
    }

    func testCanceledRequestsDoNotDecode() async throws {
        let probe = DecoderProbe()
        let repository = ImageRepository(decoder: probe)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await repository.load(URL(fileURLWithPath: "/test.jpg"))
        }
        do { _ = try await task.value; XCTFail("Canceled load delivered an image") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(probe.observations.0, 0)
    }

    func testFailuresStillReturnNavigationForRecovery() async throws {
        let folder = try TemporaryFolder()
        let url = try folder.file("corrupt.jpg")
        let result = try await ImageRepository().load(url, includeNavigation: true)
        XCTAssertThrowsError(try result.image.get())
        XCTAssertEqual(result.navigator?.currentURL, url)
    }
}
