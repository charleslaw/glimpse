import AppKit
import XCTest
@testable import GlimpseCore

private final class CachingDecoderProbe: ImageDecoding, @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private let onDecode: @Sendable (URL, Int) -> Void

    init(onDecode: @escaping @Sendable (URL, Int) -> Void = { _, _ in }) { self.onDecode = onDecode }

    func count(_ url: URL) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts[url.lastPathComponent, default: 0]
    }

    func decode(_ url: URL) throws -> NSImage {
        lock.lock()
        counts[url.lastPathComponent, default: 0] += 1
        let count = counts[url.lastPathComponent, default: 0]
        lock.unlock()
        onDecode(url, count)
        return NSImage(size: NSSize(width: 2, height: 2))
    }
}

final class ImageCacheTests: XCTestCase {
    func testRepeatedLoadUsesDecodedImageCache() async throws {
        let folder = try TemporaryFolder(), probe = CachingDecoderProbe()
        let url = try folder.file("a.png")
        let repository = ImageRepository(decoder: probe)
        _ = try await repository.load(url)
        _ = try await repository.load(url)
        XCTAssertEqual(probe.count(url), 1)
    }

    func testEditedFileInvalidatesItsCacheEntry() async throws {
        let folder = try TemporaryFolder(), probe = CachingDecoderProbe()
        let url = try folder.file("a.png")
        let repository = ImageRepository(decoder: probe)
        _ = try await repository.load(url)
        try Data([1]).write(to: url)
        _ = try await repository.load(url)
        XCTAssertEqual(probe.count(url), 2)
    }

    func testCacheNeverExceedsItsByteAndEntryLimits() async throws {
        let folder = try TemporaryFolder(), probe = CachingDecoderProbe()
        let first = try folder.file("a.png"), second = try folder.file("b.png")
        let repository = ImageRepository(decoder: probe, cacheByteLimit: 64, maximumCachedImages: 1)
        _ = try await repository.load(first)
        _ = try await repository.load(second)
        let bytes = await repository.cachedByteCount
        XCTAssertLessThanOrEqual(bytes, 64)
        _ = try await repository.load(first)
        XCTAssertEqual(probe.count(first), 2)
    }

    func testPrefetchedImageDoesNotNeedDecodingAgain() async throws {
        let folder = try TemporaryFolder()
        let url = try folder.file("next.png")
        let ready = expectation(description: "Neighbor decoded")
        let probe = CachingDecoderProbe { _, _ in ready.fulfill() }
        let repository = ImageRepository(decoder: probe)
        await repository.prefetch([url])
        await fulfillment(of: [ready], timeout: 2)
        _ = try await repository.load(url)
        XCTAssertEqual(probe.count(url), 1)
    }

    func testChangedFileDoesNotReuseAnInFlightStalePrefetch() async throws {
        let folder = try TemporaryFolder()
        let url = try folder.file("next.png")
        let started = expectation(description: "Prefetch started")
        let release = DispatchSemaphore(value: 0)
        let probe = CachingDecoderProbe { _, count in
            if count == 1 { started.fulfill(); _ = release.wait(timeout: .now() + 2) }
        }
        let repository = ImageRepository(decoder: probe)
        await repository.prefetch([url])
        await fulfillment(of: [started], timeout: 2)
        try Data([1]).write(to: url)
        // A separate foreground worker must proceed even while the stale prefetch is blocked.
        _ = try await repository.load(url)
        release.signal()
        XCTAssertEqual(probe.count(url), 2)
    }

    func testAdjacentPrefetchOrderFollowsNavigationAndWraps() throws {
        let folder = try TemporaryFolder()
        let a = try folder.file("a.jpg"), b = try folder.file("b.jpg"), c = try folder.file("c.jpg")
        var navigator = FileNavigator(currentURL: a)
        XCTAssertEqual(navigator.adjacentURLs, [b, c])
        navigator.moveToPrevious()
        XCTAssertEqual(navigator.currentURL, c)
        XCTAssertEqual(navigator.adjacentURLs, [b, a])
    }

    func testTwoImageFolderDoesNotPreloadTheSameNeighborTwice() throws {
        let folder = try TemporaryFolder()
        let first = try folder.file("a.jpg"), second = try folder.file("b.jpg")
        XCTAssertEqual(FileNavigator(currentURL: first).adjacentURLs, [second])
    }
}
