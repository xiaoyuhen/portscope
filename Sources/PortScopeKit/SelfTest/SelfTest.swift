import Foundation

/// Minimal self-test harness.
///
/// PortScope has to build on machines that only have Apple's Command Line
/// Tools, which ship neither XCTest nor the Swift Testing macro plugin. So the
/// checks live in the library and run through the binary itself:
///
///     PortScope --selftest
///
/// The same entry point is what CI calls.
public enum SelfTest {
    public struct Result: Sendable {
        public var name: String
        public var passed: Bool
        public var detail: String
    }

    /// Every check, in run order. Each entry is a name and a body that throws
    /// on failure. `async` bodies are awaited in order, so checks that spawn
    /// processes cannot interleave with each other.
    private static var checks: [(String, () async throws -> Void)] {
        // Built up in separate steps: one long concatenation of tuples times
        // out the type checker on older Swift toolchains (CI caught this).
        var all: [(String, () async throws -> Void)] = []
        let synchronous = LocalizationChecks.all
            + PortInfoChecks.all
            + ScannerChecks.all
            + IdentifierChecks.all
            + ResourceChecks.all
        for (name, body) in synchronous {
            all.append((name, { try body() }))
        }
        all.append(contentsOf: ProcessControlChecks.all)
        all.append(contentsOf: BackgroundClassificationChecks.all)
        all.append(contentsOf: PortListModelChecks.all)
        return all
    }

    @discardableResult
    public static func run() async -> [Result] {
        var results: [Result] = []
        for (name, body) in checks {
            do {
                try await body()
                results.append(Result(name: name, passed: true, detail: ""))
            } catch {
                results.append(Result(name: name, passed: false, detail: "\(error)"))
            }
        }
        return results
    }

    /// Runs the checks, prints a summary, and returns a process exit code.
    public static func main() -> Int32 {
        let results = runBlocking()
        for result in results {
            let mark = result.passed ? "  ok  " : " FAIL "
            print("[\(mark)] \(result.name)")
            if !result.passed { print("         \(result.detail)") }
        }
        let failed = results.filter { !$0.passed }.count
        print("\n\(results.count - failed) passed, \(failed) failed")
        return failed == 0 ? 0 : 1
    }

    /// Bridges the async checks to the synchronous entry point. The harness has
    /// no run loop, so this blocks the main thread while the checks run on a
    /// detached task.
    private static func runBlocking() -> [Result] {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var results: [Result] = []
        Task.detached {
            results = await run()
            semaphore.signal()
        }
        semaphore.wait()
        return results
    }
}

/// Thrown by a check body to report a failure with a readable message.
struct CheckFailure: Error, CustomStringConvertible {
    var description: String
}

func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
    if !condition { throw CheckFailure(description: message()) }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
    if actual != expected {
        throw CheckFailure(description: "\(label): expected \(expected), got \(actual)")
    }
}
