import Foundation
import PortScopeKit

/// `PortScope --list [--json]` — the same engine the UI uses, printed.
///
/// This exists for two reasons: it makes the scanner testable from a terminal
/// (and from CI) before the window is built, and it gives a scriptable view of
/// the machine that `lsof` users will want anyway.
enum ListCommand {
    static func handleIfNeeded() -> Bool {
        let args = CommandLine.arguments
        guard args.contains("--list") else { return false }
        let json = args.contains("--json")
        run(json: json)
        return true
    }

    private static func run(json: Bool) {
        // The scanner is an actor; a command-line entry point can afford to
        // block on it with a semaphore rather than spin up a run loop.
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var snapshot: PortSnapshot?
        Task.detached {
            let scanner = PortScanner()
            snapshot = await scanner.snapshot()
            semaphore.signal()
        }
        semaphore.wait()

        guard let snapshot else {
            FileHandle.standardError.write(Data("PortScope: scan failed\n".utf8))
            exit(1)
        }

        if json {
            printJSON(snapshot.ports)
        } else {
            printTable(snapshot.ports)
        }
    }

    private static func printJSON(_ ports: [PortInfo]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(ports),
              let text = String(data: data, encoding: .utf8) else {
            FileHandle.standardError.write(Data("PortScope: could not encode\n".utf8))
            exit(1)
        }
        print(text)
    }

    private static func printTable(_ ports: [PortInfo]) {
        guard !ports.isEmpty else {
            print("No listening TCP ports.")
            return
        }
        let header = ["PORT", "BIND", "PID", "PROCESS", "CWD"]
        var rows: [[String]] = ports.map { info in
            [
                String(info.port),
                info.addresses.joined(separator: ","),
                String(info.pid),
                info.displayName,
                info.workingDirectory ?? "-",
            ]
        }
        rows.insert(header, at: 0)

        let widths = (0..<header.count).map { column in
            rows.map { $0[column].count }.max() ?? 0
        }
        for row in rows {
            let line = row.enumerated().map { column, value in
                value.padding(toLength: widths[column], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
            print(line)
        }
    }
}
