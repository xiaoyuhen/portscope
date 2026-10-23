import Darwin
import Foundation

/// Checks for the code that signals processes. This is the most dangerous part
/// of the app, so the refusals are tested directly rather than trusted.
enum ProcessControlChecks {
    static var all: [(String, () async throws -> Void)] {
        [
            ("PortScope never signals itself", {
                let controller = ProcessController()
                try expectEqual(controller.refusalReason(for: getpid()), .ownProcess, "self")
            }),
            ("PortScope never signals launchd", {
                let controller = ProcessController()
                try expectEqual(controller.refusalReason(for: 1), .systemProcess, "pid 1")
            }),
            ("a process we do not own is refused", {
                // launchd runs as root; this check is skipped when the harness
                // itself runs as root, where ownership proves nothing.
                guard getuid() != 0 else { return }
                let controller = ProcessController()
                try expectEqual(controller.refusalReason(for: 1), .systemProcess, "pid 1")
            }),
            ("a pid that does not exist is reported as gone", {
                let controller = ProcessController()
                // PIDs are allocated well below this on macOS.
                try expectEqual(controller.refusalReason(for: 999_999), .processGone, "missing pid")
            }),
            ("a child process is found among the descendants", {
                let child = try SpawnedChild()
                defer { child.terminate() }
                let controller = ProcessController()
                try expect(controller.descendants(of: getpid()).contains(child.pid),
                           "child \\(child.pid) not found")
            }),
            ("stopping a child terminates it and reports success", {
                let child = try SpawnedChild()
                let controller = ProcessController(gracePeriod: 2)
                let outcome = await controller.stop(pid: child.pid)
                try expect(outcome.success, "outcome: \\(outcome)")
                try expect(!controller.isRunning(child.pid), "child still running")
            }),
            ("arguments are quoted so they cannot escape the shell", {
                let quoted = ProcessController.quote("hello; rm -rf /")
                try expectEqual(quoted, "'hello; rm -rf /'", "semicolon")
                try expectEqual(ProcessController.quote("it's"), "'it'\\''s'", "apostrophe")
                try expectEqual(ProcessController.quote("a b"), "'a b'", "space")
            }),
            ("a restart command replays the original argv", {
                let info = fixtureInfo(arguments: ["node", "scripts/dev.js", "--port", "3000"])
                let controller = ProcessController()
                try expectEqual(
                    controller.restartCommand(for: info),
                    "'node' 'scripts/dev.js' '--port' '3000'",
                    "command"
                )
            }),
            ("a restart command falls back to the executable path", {
                let info = fixtureInfo(arguments: [])
                let controller = ProcessController()
                try expectEqual(
                    controller.restartCommand(for: info),
                    "'/usr/local/bin/node'",
                    "command"
                )
            }),
        ]
    }

    private static func fixtureInfo(arguments: [String]) -> PortInfo {
        PortInfo(
            port: 3000, addresses: ["127.0.0.1"], exposure: .loopback,
            pid: 4242, processName: "node",
            executablePath: "/usr/local/bin/node",
            arguments: arguments, workingDirectory: nil,
            uptime: 10, appBundleName: nil, service: nil
        )
    }
}

/// A real child process that sleeps, used to exercise termination.
private final class SpawnedChild {
    let pid: pid_t
    private let process: Process

    init() throws {
        process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        pid = process.processIdentifier
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}
