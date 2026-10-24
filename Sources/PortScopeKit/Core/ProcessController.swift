import Darwin
import Foundation

/// Why an action was refused. These are returned rather than thrown so the UI
/// can explain the refusal instead of just failing.
public enum ProcessControlRefusal: Sendable, Equatable {
    /// PortScope will not signal itself or its own helper processes.
    case ownProcess
    /// PID 1 and kernel processes are never signalled.
    case systemProcess
    /// The process belongs to another user; signalling it needs privileges we
    /// deliberately do not ask for.
    case otherUser
    /// The process no longer exists — it exited between the scan and the click.
    case processGone
}

/// What happened when we tried to stop something.
public struct StopOutcome: Sendable, Equatable {
    public var terminated: [pid_t]
    public var forceKilled: [pid_t]
    public var refused: [pid_t: ProcessControlRefusal]
    /// True when every process we targeted is gone.
    public var success: Bool
}

/// Stops processes and restarts services.
///
/// Three rules shape everything here:
///
/// 1. **Never signal what we do not own.** Only processes owned by the current
///    user, never PID 1, never PortScope itself. A port monitor that can kill
///    arbitrary system services is a liability, not a tool.
/// 2. **Ask before SIGTERM, escalate to SIGKILL.** Services get a grace period
///    to clean up (Redis flushes, Node closes sockets); only then is SIGKILL
///    used, and the UI reports that it happened.
/// 3. **Take the children with it.** A dev server usually owns a child process
///    (a compiler, a database). Killing only the port owner orphans them, and
///    they keep the port busy — the restart then fails with "address in use".
public actor ProcessController {
    private let gracePeriod: TimeInterval

    public init(gracePeriod: TimeInterval = 3) {
        self.gracePeriod = gracePeriod
    }

    // MARK: - Stopping

    /// Stops `pid` and all of its descendants.
    ///
    /// A refused root stops *nothing*. The descendants are only taken because
    /// they belong to the service being stopped; when the root is not ours to
    /// stop, its descendants are someone else's business too. Walking them
    /// anyway is not a theoretical risk: launchd (PID 1) holds the listening
    /// sockets of socket-activated services, and every process in the login
    /// session descends from it, so stopping such a row would have signalled
    /// the whole session.
    public func stop(pid: pid_t) async -> StopOutcome {
        var outcome = StopOutcome(terminated: [], forceKilled: [], refused: [:], success: false)
        if let refusal = refusalReason(for: pid) {
            outcome.refused[pid] = refusal
            return outcome
        }

        let plan = Self.stopPlan(root: pid, children: childrenByParent(), refusal: refusalReason)
        outcome.refused = plan.refused
        let permitted = plan.permitted
        guard !permitted.isEmpty else { return outcome }

        // Children first: stopping the parent first can orphan them before we
        // get to them.
        for target in permitted.reversed() where isRunning(target) {
            if kill(target, SIGTERM) == 0 {
                outcome.terminated.append(target)
            }
        }

        // Wait for the grace period, then force what is left.
        let deadline = Date().addingTimeInterval(gracePeriod)
        while Date() < deadline {
            if permitted.allSatisfy({ !isRunning($0) }) { break }
            try? await Task.sleep(for: .milliseconds(120))
        }
        for target in permitted where isRunning(target) {
            if kill(target, SIGKILL) == 0 {
                outcome.forceKilled.append(target)
            }
        }

        // Give the kernel a moment to reap before the caller rescans.
        try? await Task.sleep(for: .milliseconds(150))
        outcome.success = permitted.allSatisfy { !isRunning($0) }
        return outcome
    }

    // MARK: - Restarting

    public enum RestartError: Error, Sendable {
        /// We know the pid but not enough about it to re-run it.
        case unknownCommand
        /// The old process could not be stopped, so starting a second copy
        /// would either fail on "address in use" or, worse, look like success
        /// because the old one is still holding the port.
        case stopFailed(ProcessControlRefusal?)
        case directoryMissing(String)
        case spawnFailed(String)
        case portDidNotComeBack(Int)
    }

    /// Restarts the service that was listening on `port`.
    ///
    /// The command line is replayed through a login shell (`zsh -lc`) so the
    /// process inherits the user's PATH — a `node` started from an nvm-managed
    /// shell does not exist for a process that only inherits PortScope's own
    /// environment. Arguments are single-quoted, so an argument containing
    /// spaces or shell syntax cannot escape into a second command.
    ///
    /// The original environment is *not* restored: PortScope deliberately never
    /// reads it (it holds API keys), so a restart gets the shell's environment
    /// rather than the one the service originally ran with.
    public func restart(info: PortInfo, waitForPort timeout: TimeInterval = 20) async throws -> pid_t {
        guard let command = restartCommand(for: info) else {
            throw RestartError.unknownCommand
        }
        if let cwd = info.workingDirectory {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw RestartError.directoryMissing(cwd)
            }
        }

        let stopped = await stop(pid: info.pid)
        // A service that already exited has nothing to stop; starting it again
        // is exactly what was asked for.
        if !stopped.success, stopped.refused[info.pid] != .processGone {
            throw RestartError.stopFailed(stopped.refused.values.first)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        if let cwd = info.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        // Detach from PortScope: the service must outlive the window.
        process.standardInput = FileHandle.nullDevice
        let logURL = try logFile(for: info.port)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try? FileHandle(forWritingTo: logURL)
        if let handle {
            process.standardOutput = handle
            process.standardError = handle
        }
        // The child has its own copy of the descriptor once it is running;
        // PortScope's copy would otherwise leak one fd per restart.
        defer { try? handle?.close() }

        do {
            try process.run()
        } catch {
            throw RestartError.spawnFailed(error.localizedDescription)
        }

        let pid = process.processIdentifier
        // Confirm the port actually came back; a process that starts and dies
        // immediately would otherwise look like a successful restart.
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(250))
            if LibprocScanner.scan().contains(where: { $0.port == info.port }) {
                return pid
            }
            if !isRunning(pid) {
                throw RestartError.spawnFailed("the process exited during startup")
            }
        }
        throw RestartError.portDidNotComeBack(info.port)
    }

    /// Where restart output goes, so a service that fails to start can be
    /// diagnosed instead of vanishing silently.
    public nonisolated func logFile(for port: Int) throws -> URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/PortScope", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("port-\(port).log")
    }

    /// The command to replay. Prefers argv as the kernel reports it, because
    /// that is what actually ran — including flags a person has forgotten.
    public nonisolated func restartCommand(for info: PortInfo) -> String? {
        let arguments = info.arguments.filter { !$0.isEmpty }
        guard !arguments.isEmpty else {
            guard let path = info.executablePath else { return nil }
            return Self.quote(path)
        }
        return arguments.map(Self.quote).joined(separator: " ")
    }

    /// POSIX single-quote quoting. Inside single quotes every character is
    /// literal, so the only thing to handle is the quote itself.
    public nonisolated static func quote(_ argument: String) -> String {
        "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Safety

    /// Nil when it is safe to signal `pid`.
    public nonisolated func refusalReason(for pid: pid_t) -> ProcessControlRefusal? {
        guard pid > 1 else { return .systemProcess }
        if pid == getpid() || pid == getppid() { return .ownProcess }

        var info = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard size == MemoryLayout<proc_bsdinfo>.size else { return .processGone }
        guard info.pbi_uid == getuid() else { return .otherUser }
        return nil
    }

    public nonisolated func isRunning(_ pid: pid_t) -> Bool {
        // Signal 0 performs the permission and existence checks without
        // delivering anything.
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// The processes a stop of `root` may signal, breadth-first, root first.
    ///
    /// A refused process is recorded and its subtree is not entered: a process
    /// we may not signal is a boundary, and whatever runs under it belongs to
    /// it rather than to the service being stopped. Pure, so the rule is
    /// checked without signalling anything.
    static func stopPlan(
        root: pid_t,
        children: [pid_t: [pid_t]],
        refusal: (pid_t) -> ProcessControlRefusal?
    ) -> (permitted: [pid_t], refused: [pid_t: ProcessControlRefusal]) {
        var permitted: [pid_t] = []
        var refused: [pid_t: ProcessControlRefusal] = [:]
        var seen: Set<pid_t> = []
        var queue = [root]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            // Guard against a pathological cycle rather than looping forever.
            guard seen.insert(next).inserted else { continue }
            if let reason = refusal(next) {
                refused[next] = reason
                continue
            }
            permitted.append(next)
            queue.append(contentsOf: children[next] ?? [])
        }
        return (permitted, refused)
    }

    /// All descendants of `pid`, breadth-first.
    public nonisolated func descendants(of pid: pid_t) -> [pid_t] {
        Self.stopPlan(root: pid, children: childrenByParent(), refusal: { _ in nil })
            .permitted.dropFirst().map { $0 }
    }

    /// Every live process, keyed by its parent.
    nonisolated func childrenByParent() -> [pid_t: [pid_t]] {
        var childrenByParent: [pid_t: [pid_t]] = [:]
        for candidate in LibprocScanner.allPids() {
            var info = proc_bsdinfo()
            let size = proc_pidinfo(
                candidate, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)
            )
            guard size == MemoryLayout<proc_bsdinfo>.size else { continue }
            let parent = pid_t(info.pbi_ppid)
            guard parent != candidate else { continue }
            childrenByParent[parent, default: []].append(candidate)
        }
        return childrenByParent
    }
}
