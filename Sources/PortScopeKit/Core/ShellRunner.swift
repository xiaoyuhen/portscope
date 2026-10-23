import Foundation

/// Result of running a child process to completion.
struct CommandResult: Sendable {
    var exitCode: Int32
    var stdout: String
    var stderr: String

    var succeeded: Bool { exitCode == 0 }
    var trimmedOut: String { stdout.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Runs system tools (`ps`, `lsof`, `kill`, …) directly, never through a shell.
///
/// Nothing here is ever string-interpolated into a shell command line: the
/// binary and each argument are passed as separate `Process` arguments. That
/// keeps a hostile or merely weird process name from turning into shell syntax
/// when it shows up in a command we run.
enum ShellRunner {
    /// Absolute paths only. Resolving through PATH would let a planted binary
    /// earlier in the path win.
    static func run(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval = 5,
        environment: [String: String]? = nil
    ) async -> CommandResult {
        let state = RunState()
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let environment {
                process.environment =
                    ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            // Don't inherit stdin: some tools will otherwise block waiting on it.
            process.standardInput = FileHandle.nullDevice

            state.out = PipeReader(handle: outPipe.fileHandleForReading)
            state.err = PipeReader(handle: errPipe.fileHandleForReading)
            state.process = process
            state.out?.start()
            state.err?.start()

            process.terminationHandler = { finished in
                state.cancelTimeout()
                state.out?.waitUntilFinished()
                state.err?.waitUntilFinished()
                continuation.resume(returning: CommandResult(
                    exitCode: finished.terminationStatus,
                    stdout: state.out?.text ?? "",
                    stderr: state.err?.text ?? ""
                ))
            }

            do {
                try process.run()
            } catch {
                state.cancelTimeout()
                continuation.resume(returning: CommandResult(
                    exitCode: -1, stdout: "", stderr: error.localizedDescription
                ))
                return
            }

            // A tool that ignores SIGTERM (or hangs on a locked file) must not
            // wedge the poll loop, so escalate to SIGKILL after the timeout.
            let item = DispatchWorkItem { [process] in
                guard process.isRunning else { return }
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
            state.setTimeoutItem(item)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
        }
    }
}

/// Mutable hand-off between the timeout timer and the termination handler.
/// Only the timeout item is touched concurrently, and it is guarded by a lock.
private final class RunState: @unchecked Sendable {
    var process: Process?
    var out: PipeReader?
    var err: PipeReader?

    private let lock = NSLock()
    private var timeoutItem: DispatchWorkItem?

    func setTimeoutItem(_ item: DispatchWorkItem) {
        lock.lock()
        timeoutItem = item
        lock.unlock()
    }

    func cancelTimeout() {
        lock.lock()
        let item = timeoutItem
        timeoutItem = nil
        lock.unlock()
        item?.cancel()
    }
}

/// Collects a pipe's bytes off the main thread.
final class PipeReader: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var data = Data()
    private let done = DispatchSemaphore(value: 0)

    init(handle: FileHandle) { self.handle = handle }

    func start() {
        let handle = self.handle
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let bytes = handle.readDataToEndOfFile()
            guard let self else { return }
            self.lock.lock()
            self.data = bytes
            self.lock.unlock()
            self.done.signal()
        }
    }

    func waitUntilFinished() { done.wait() }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
