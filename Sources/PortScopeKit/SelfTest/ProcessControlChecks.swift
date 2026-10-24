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
                let info = fixtureInfo(arguments: ["/opt/bin/node", "scripts/dev.js", "--port", "3000"])
                let controller = ProcessController()
                try expectEqual(
                    controller.restartCommand(for: info),
                    "'/opt/bin/node' 'scripts/dev.js' '--port' '3000'",
                    "command"
                )
            }),
            ("a bare argv[0] is replayed as the running executable", {
                // npm spawns `node …` by name. The replay shell does not read
                // .zshrc, where nvm lives, so the name alone is not found.
                let info = fixtureInfo(arguments: ["node", "scripts/dev.js"])
                let controller = ProcessController()
                try expectEqual(
                    controller.restartCommand(for: info),
                    "'/usr/local/bin/node' 'scripts/dev.js'",
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
            // None of the checks below signal anything outside this process's
            // own children. A refused root used to have its descendants
            // signalled anyway, and for PID 1 that is the whole login session,
            // so "can PortScope stop launchd's children" is answered with the
            // pure planner and with this process as the refused root — never
            // by pointing a real stop at a system process.
            ("a refused root plans no targets at all", {
                let children: [pid_t: [pid_t]] = [1: [100, 200], 100: [101]]
                let plan = ProcessController.stopPlan(
                    root: 1, children: children,
                    refusal: { $0 == 1 ? .systemProcess : nil }
                )
                try expectEqual(plan.permitted, [], "permitted")
                try expectEqual(plan.refused, [1: .systemProcess], "refused")
            }),
            ("a refused descendant fences off its own subtree", {
                // 10 is ours, 20 is another user's helper, 21 runs under it.
                let children: [pid_t: [pid_t]] = [10: [11, 20], 20: [21]]
                let plan = ProcessController.stopPlan(
                    root: 10, children: children,
                    refusal: { $0 == 20 ? .otherUser : nil }
                )
                try expectEqual(plan.permitted, [10, 11], "permitted")
                try expectEqual(plan.refused, [20: .otherUser], "refused")
            }),
            ("stopping a refused root leaves its children running", {
                let child = try SpawnedChild()
                defer { child.terminate() }
                let controller = ProcessController(gracePeriod: 0.2)
                // This process is refused as `.ownProcess`; its child is ours.
                let outcome = await controller.stop(pid: getpid())
                try expect(!outcome.success, "outcome: \(outcome)")
                try expectEqual(outcome.refused, [getpid(): .ownProcess], "refused")
                try expect(controller.isRunning(child.pid), "the child was signalled")
            }),
            ("a restart that cannot stop the old process starts nothing", {
                // The old process is still holding the port, so a second copy
                // would either die on "address in use" or be reported as a
                // successful restart because the port is (still) listening.
                let marker = FileManager.default.temporaryDirectory
                    .appendingPathComponent("portscope-restart-\(UUID().uuidString)")
                let info = fixtureInfo(arguments: ["/usr/bin/touch", marker.path], pid: getpid())
                let controller = ProcessController(gracePeriod: 0.2)
                do {
                    _ = try await controller.restart(info: info, waitForPort: 1)
                    throw CheckFailure(description: "a refused restart reported success")
                } catch ProcessController.RestartError.stopFailed(let refusal) {
                    try expectEqual(refusal, .ownProcess, "refusal")
                }
                try? await Task.sleep(for: .milliseconds(300))
                try expect(!FileManager.default.fileExists(atPath: marker.path),
                           "the replacement was spawned anyway")
            }),
        ]
    }

    private static func fixtureInfo(arguments: [String], pid: pid_t = 4242) -> PortInfo {
        PortInfo(
            port: 3000, addresses: ["127.0.0.1"], exposure: .loopback,
            pid: pid, processName: "node",
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
