import Foundation
import Darwin

/// Shared by image decoding, metadata inspection, and actions config loading.
enum BoundedLocalFileReader {
    enum Failure: Error, LocalizedError {
        case notLocal, notRegular, tooLarge
        var errorDescription: String? {
            switch self {
            case .notLocal: return "Choose a local file."
            case .notRegular: return "The selected item is not a readable, regular file."
            case .tooLarge: return "The file exceeds the size limit."
            }
        }
    }

    static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        guard url.isFileURL else { throw Failure.notLocal }
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw Failure.notRegular }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { throw Failure.notRegular }
        guard maximumBytes >= 0, maximumBytes < Int.max, info.st_size >= 0,
              info.st_size <= maximumBytes else { throw Failure.tooLarge }
        var data = Data()
        while true {
            try Task.checkCancellation()
            let remaining = maximumBytes - data.count + 1
            guard let chunk = try file.read(upToCount: min(1_048_576, remaining)), !chunk.isEmpty else { break }
            data.append(chunk)
            guard data.count <= maximumBytes else { throw Failure.tooLarge }
        }
        return data
    }
}
