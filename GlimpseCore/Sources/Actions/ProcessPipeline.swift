import Foundation

/// Nonblocking execution of already resolved/validated stages. Confirmation and
/// executable policy belong to the app's ActionRunner, not this I/O service.
@MainActor
public final class ProcessPipeline {
    private let commands: [ActionCommand]
    private let directory: URL
    private let output: FileHandle
    private let timeoutNanoseconds: UInt64
    private let onComplete: ([Int32]) -> Void
    private var processes: [Process] = []
    private var pipes: [Pipe] = []
    private var statuses: [Int32?] = []
    private var deadline: Task<Void, Never>?
    private var finished = false
    private var started = false

    public var isRunning: Bool { processes.contains(where: \.isRunning) }

    public init(commands: [ActionCommand], directory: URL, output: FileHandle = .nullDevice,
                timeoutNanoseconds: UInt64 = 30_000_000_000, onComplete: @escaping ([Int32]) -> Void) {
        self.commands = commands
        self.directory = directory
        self.output = output
        self.timeoutNanoseconds = timeoutNanoseconds
        self.onComplete = onComplete
    }

    public func start() throws {
        guard !started, !finished, !commands.isEmpty, commands.count <= 4 else {
            throw ActionsConfigurationError.invalid("An action needs one to four commands and can be started only once.")
        }
        started = true
        statuses = commands.map { _ in nil }
        pipes = (0..<(commands.count - 1)).map { _ in Pipe() }
        processes = commands.enumerated().map { index, command in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
            process.currentDirectoryURL = directory
            process.standardInput = index == 0 ? FileHandle.nullDevice : pipes[index - 1].fileHandleForReading
            process.standardOutput = index == commands.count - 1 ? output : pipes[index].fileHandleForWriting
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] process in
                let status = process.terminationStatus
                Task { @MainActor [weak self] in self?.completed(index, status: status) }
            }
            return process
        }
        do {
            // Start consumers first, then producers. Children inherit duplicated
            // handles; closing our copies below lets consumers receive EOF.
            for process in processes.reversed() { try process.run() }
            closePipes()
        } catch {
            cancel()
            throw error
        }
        deadline = Task { @MainActor [weak self] in
            guard let duration = self?.timeoutNanoseconds else { return }
            do { try await Task.sleep(nanoseconds: duration) } catch { return }
            self?.processes.filter(\.isRunning).forEach { $0.terminate() }
        }
    }

    public func cancel() {
        finished = true
        deadline?.cancel()
        deadline = nil
        closePipes()
        processes.filter(\.isRunning).forEach { $0.terminate() }
    }

    private func closePipes() {
        for pipe in pipes {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
        pipes.removeAll()
    }

    private func completed(_ index: Int, status: Int32) {
        guard !finished else { return }
        statuses[index] = status
        guard statuses.allSatisfy({ $0 != nil }) else { return }
        finished = true
        deadline?.cancel()
        deadline = nil
        onComplete(statuses.compactMap { $0 })
    }
}
