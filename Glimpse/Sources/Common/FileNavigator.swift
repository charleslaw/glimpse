import Foundation

/// Maintains a sorted list of image siblings in the same folder as the
/// currently-displayed file, and allows stepping forward/backward through them.
final class FileNavigator {

    // MARK: - Properties

    private(set) var currentURL: URL
    private var imageURLs: [URL] = []
    private var currentIndex: Int = 0

    // MARK: - Init

    init(currentURL: URL) {
        self.currentURL = currentURL
        loadSiblings()
    }

    // MARK: - Navigation

    func moveToNext() {
        guard !imageURLs.isEmpty else { return }
        currentIndex = (currentIndex + 1) % imageURLs.count
        currentURL = imageURLs[currentIndex]
    }

    func moveToPrevious() {
        guard !imageURLs.isEmpty else { return }
        currentIndex = (currentIndex - 1 + imageURLs.count) % imageURLs.count
        currentURL = imageURLs[currentIndex]
    }

    // MARK: - Accessors

    /// 1-based position for display purposes (e.g. "3 of 15").
    var position: Int { currentIndex + 1 }

    /// Total number of images found in the folder.
    var totalCount: Int { imageURLs.count }

    // MARK: - Private

    private func loadSiblings() {
        let directory = currentURL.deletingLastPathComponent()

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            imageURLs = contents
                .filter { ImageLoader.supportedExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            currentIndex = imageURLs.firstIndex(of: currentURL) ?? 0

        } catch {
            // Fall back gracefully: just show the single file
            imageURLs = [currentURL]
            currentIndex = 0
        }
    }
}
