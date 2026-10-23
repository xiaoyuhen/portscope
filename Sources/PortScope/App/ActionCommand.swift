import Foundation
import PortScopeKit

/// `PortScope --stop <port>` and `PortScope --restart <port>`.
///
/// The same `ProcessController` the UI uses, exposed on the command line. It
/// makes the destructive paths testable end-to-end without clicking, and it is
/// the obvious thing to reach for from a script.
enum ActionCommand {
    static func handleIfNeeded() -> Bool {
        let args = CommandLine.arguments
        let isStop = args.contains("--stop")
        let isRestart = args.contains("--restart")
        guard isStop || isRestart else { return false }

        guard let flagIndex = args.firstIndex(where: { $0 == "--stop" || $0 == "--restart" }),
              flagIndex + 1 < args.count, let port = Int(args[flagIndex + 1]) else {
            FileHandle.standardError.write(Data("usage: PortScope --stop|--restart <port>\n".utf8))
            exit(2)
        }

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var exitCode: Int32 = 0
        Task.detached {
            exitCode = await run(port: port, restart: isRestart)
            semaphore.signal()
        }
        semaphore.wait()
        exit(exitCode)
    }

    private static func run(port: Int, restart: Bool) async -> Int32 {
        let snapshot = await PortScanner(probeHTTP: false).snapshot()
        guard let info = snapshot.ports.first(where: { $0.port == port }) else {
            FileHandle.standardError.write(Data("PortScope: nothing is listening on \(port)\n".utf8))
            return 1
        }

        let controller = ProcessController()
        if !restart {
            let outcome = await controller.stop(pid: info.pid)
            if outcome.success {
                print("stopped \(info.processName) (pid \(info.pid)) on port \(port)")
                return 0
            }
            for (pid, refusal) in outcome.refused {
                FileHandle.standardError.write(Data("refused \(pid): \(refusal)\n".utf8))
            }
            return 1
        }

        do {
            let pid = try await controller.restart(info: info)
            print("restarted on port \(port) as pid \(pid)")
            return 0
        } catch {
            FileHandle.standardError.write(Data("restart failed: \(error)\n".utf8))
            return 1
        }
    }
}
