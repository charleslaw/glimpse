import AppKit

/// A decoded image presented only by the main-actor viewer. Raster cache entries
/// retain immutable images; mutable animated representations are never cached.
public struct ImageLoadResult: @unchecked Sendable {
    public let image: Result<NSImage, ImageLoadingError>
    public let navigator: FileNavigator?
}

/// Per-window coordinator. Independent workers keep speculative decoding out of
/// the foreground queue, while actor-owned cache state stays race-free.
public actor ImageRepository {
    private struct Prefetch: Sendable {
        let id: UUID
        let task: Task<ImageDecodeWorker.DecodedImage, Error>
        let version: ImageFileVersion
    }
    private let foreground: ImageDecodeWorker
    private let background: ImageDecodeWorker
    private var cache: ImageMemoryCache
    private var prefetches: [URL: Prefetch] = [:]
    private var priorities: [URL] = []
    private var currentURL: URL?

    var cachedByteCount: Int { cache.byteCount }

    public init(decoder: any ImageDecoding = ImageDecoder(), cacheByteLimit: Int = 256 * 1024 * 1024,
                maximumCachedImages: Int = 3) {
        foreground = ImageDecodeWorker(decoder: decoder)
        background = ImageDecodeWorker(decoder: decoder)
        cache = ImageMemoryCache(byteLimit: cacheByteLimit, entryLimit: maximumCachedImages)
    }

    deinit { prefetches.values.forEach { $0.task.cancel() } }

    public func load(_ requestedURL: URL, includeNavigation: Bool = false) async throws -> ImageLoadResult {
        try Task.checkCancellation()
        let url = Self.canonical(requestedURL)
        guard url.isFileURL else {
            return ImageLoadResult(image: .failure(.notLocalFile), navigator: nil)
        }
        let navigator = includeNavigation ? FileNavigator(currentURL: url) : nil
        let version = ImageFileVersion(url)
        let pending = prefetches.removeValue(forKey: url)
        let prefetched: Prefetch?
        if let pending, pending.version == version { prefetched = pending }
        else { pending?.task.cancel(); prefetched = nil }
        cancelPrefetch()
        if let hit = cache.value(for: url, version: version) {
            prefetched?.task.cancel()
            currentURL = url
            return ImageLoadResult(image: .success(hit.image), navigator: navigator)
        }
        let worker = foreground
        let task = prefetched?.task ?? Task(priority: .userInitiated) { try await worker.decode(url) }
        do {
            let decoded = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: { task.cancel() }
            try Task.checkCancellation()
            if let version, ImageFileVersion(url) == version {
                cache.insert(decoded, for: url, version: version)
            }
            currentURL = url
            return ImageLoadResult(image: .success(decoded.image), navigator: navigator)
        } catch is CancellationError { throw CancellationError() }
        catch let error as ImageLoadingError {
            return ImageLoadResult(image: .failure(error), navigator: navigator)
        } catch {
            return ImageLoadResult(image: .failure(.unsupportedOrCorrupt), navigator: navigator)
        }
    }

    public func prefetch(_ urls: [URL]) {
        cancelPrefetch()
        var seen = Set<URL>()
        priorities = urls.map(Self.canonical).filter {
            $0.isFileURL && $0 != currentURL && seen.insert($0).inserted &&
            !["gif", "tif", "tiff"].contains($0.pathExtension.lowercased())
        }.prefix(2).map { $0 }
        for url in priorities {
            guard let version = ImageFileVersion(url), cache.value(for: url, version: version) == nil else { continue }
            let worker = background, id = UUID()
            let task = Task(priority: .utility) { try await worker.decode(url) }
            prefetches[url] = Prefetch(id: id, task: task, version: version)
            Task.detached { [weak self] in
                let result = await task.result
                await self?.finishPrefetch(url, id: id, version: version, result: result)
            }
        }
    }

    public func cancelPrefetch() {
        prefetches.values.forEach { $0.task.cancel() }
        prefetches.removeAll()
        priorities.removeAll()
    }

    private func finishPrefetch(_ url: URL, id: UUID, version: ImageFileVersion,
                                result: Result<ImageDecodeWorker.DecodedImage, Error>) {
        guard prefetches[url]?.id == id else { return }
        prefetches.removeValue(forKey: url)
        guard case .success(let decoded) = result, ImageFileVersion(url) == version else { return }
        var protected = Set(priorities.prefix { $0 != url })
        if let currentURL { protected.insert(currentURL) }
        cache.insert(decoded, for: url, version: version, protecting: protected)
    }

    private static func canonical(_ url: URL) -> URL {
        guard url.isFileURL else { return url }
        return url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent)
    }
}
