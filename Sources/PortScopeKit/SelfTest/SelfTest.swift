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
    /// on failure.
    private static var checks: [(String, () throws -> Void)] {
        LocalizationChecks.all + PortInfoChecks.all + ScannerChecks.all
    }

    @discardableResult
    public static func run() -> [Result] {
        checks.map { name, body in
            do {
                try body()
                return Result(name: name, passed: true, detail: "")
            } catch {
                return Result(name: name, passed: false, detail: "\(error)")
            }
        }
    }

    /// Runs the checks, prints a summary, and returns a process exit code.
    public static func main() -> Int32 {
        let results = run()
        for result in results {
            let mark = result.passed ? "  ok  " : " FAIL "
            print("[\(mark)] \(result.name)")
            if !result.passed { print("         \(result.detail)") }
        }
        let failed = results.filter { !$0.passed }.count
        print("\n\(results.count - failed) passed, \(failed) failed")
        return failed == 0 ? 0 : 1
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
