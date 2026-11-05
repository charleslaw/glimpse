import Foundation
import Darwin

struct ImageFileVersion: Equatable, Sendable {
    private let device: dev_t
    private let inode: ino_t
    private let size: off_t
    private let modified: time_t
    private let nanoseconds: Int

    init?(_ url: URL) {
        guard url.isFileURL else { return nil }
        var info = stat()
        guard Darwin.lstat(url.resolvingSymlinksInPath().path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        device = info.st_dev
        inode = info.st_ino
        size = info.st_size
        modified = info.st_mtimespec.tv_sec
        nanoseconds = info.st_mtimespec.tv_nsec
    }
}

/// Small LRU cache with byte and entry limits; owned by ImageRepository's actor.
struct ImageMemoryCache {
    private struct Entry {
        let decoded: ImageDecodeWorker.DecodedImage
        let version: ImageFileVersion
    }
    private var entries: [URL: Entry] = [:]
    private var order: [URL] = []
    private let byteLimit: Int
    private let entryLimit: Int
    private(set) var byteCount = 0

    init(byteLimit: Int, entryLimit: Int) {
        self.byteLimit = max(0, byteLimit)
        self.entryLimit = max(0, entryLimit)
    }

    mutating func value(for url: URL, version: ImageFileVersion?) -> ImageDecodeWorker.DecodedImage? {
        guard let version, let entry = entries[url], entry.version == version else { remove(url); return nil }
        order.removeAll { $0 == url }
        order.append(url)
        return entry.decoded
    }

    mutating func insert(_ decoded: ImageDecodeWorker.DecodedImage, for url: URL,
                         version: ImageFileVersion, protecting: Set<URL> = []) {
        guard decoded.cacheable, entryLimit > 0, decoded.byteCost <= byteLimit else { return }
        remove(url)
        while entries.count >= entryLimit || byteCount > byteLimit - decoded.byteCost {
            guard let victim = order.first(where: { !protecting.contains($0) }) else { return }
            remove(victim)
        }
        entries[url] = Entry(decoded: decoded, version: version)
        order.append(url)
        byteCount += decoded.byteCost
    }

    private mutating func remove(_ url: URL) {
        if let entry = entries.removeValue(forKey: url) { byteCount -= entry.decoded.byteCost }
        order.removeAll { $0 == url }
    }
}
