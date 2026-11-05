import Foundation

/// Maintains a sorted list of image siblings in the same folder as the
/// currently-displayed file, and allows stepping forward/backward through them.
public struct FileNavigator: Sendable {

    // MARK: - Properties

    public private(set) var currentURL: URL
    private var imageURLs: [URL] = []
    private var currentIndex: Int = 0
    private var prefersForward = true

    // MARK: - Init

    public init(currentURL: URL) {
        self.currentURL = currentURL.isFileURL
            ? currentURL.deletingLastPathComponent().resolvingSymlinksInPath()
                .appendingPathComponent(currentURL.lastPathComponent)
            : currentURL
        loadSiblings()
    }

    // MARK: - Navigation

    public mutating func moveToNext() {
        prefersForward = true
        guard !imageURLs.isEmpty else { return }
        currentIndex = (currentIndex + 1) % imageURLs.count
        currentURL = imageURLs[currentIndex]
    }

    public mutating func moveToPrevious() {
        prefersForward = false
        guard !imageURLs.isEmpty else { return }
        currentIndex = (currentIndex - 1 + imageURLs.count) % imageURLs.count
        currentURL = imageURLs[currentIndex]
    }

    // MARK: - Accessors

    /// 1-based position for display purposes (e.g. "3 of 15").
    public var position: Int { currentIndex + 1 }

    /// Total number of images found in the folder.
    public var totalCount: Int { imageURLs.count }

    public var adjacentURLs: [URL] {
        guard imageURLs.count > 1 else { return [] }
        var seen = Set<URL>()
        return (prefersForward ? [1, -1] : [-1, 1]).compactMap { offset in
            let url = imageURLs[(currentIndex + offset + imageURLs.count) % imageURLs.count]
            return url != currentURL && seen.insert(url).inserted ? url : nil
        }
    }

    // MARK: - Private

    private mutating func loadSiblings() {
        guard currentURL.isFileURL else {
            imageURLs = [currentURL]
            return
        }
        let directory = currentURL.deletingLastPathComponent()

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            imageURLs = contents
                .map {
                    $0.deletingLastPathComponent().resolvingSymlinksInPath()
                        .appendingPathComponent($0.lastPathComponent)
                }
                .filter {
                    ImageFormats.supportedExtensions.contains($0.pathExtension.lowercased()) &&
                    (try? $0.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
                }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            // Preserve explicitly opened hidden or unrecognised-extension images.
            if !imageURLs.contains(currentURL) {
                imageURLs.append(currentURL)
                imageURLs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            }
            currentIndex = imageURLs.firstIndex(of: currentURL) ?? 0

        } catch {
            // Fall back gracefully: just show the single file
            imageURLs = [currentURL]
            currentIndex = 0
        }
    }
}
