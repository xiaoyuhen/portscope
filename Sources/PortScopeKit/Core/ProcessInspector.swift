import Darwin
import Foundation

/// Everything the kernel will tell us about one process.
public struct ProcessDetails: Sendable, Hashable {
    var pid: pid_t
    var name: String
    var executablePath: String?
    var arguments: [String]
    var workingDirectory: String?
    var parentPID: pid_t?
    var startedAt: Date?
    var appBundlePath: String?

    /// The `.app` a process lives inside, if any. `/Applications/Slack.app/…`
    /// yields "Slack"; a bare `/usr/bin/node` yields nil.
    var appBundleName: String? {
        guard let path = appBundlePath else { return nil }
        let name = (path as NSString).lastPathComponent
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

/// Reads process metadata through `libproc` and `sysctl`.
///
/// Expensive fields (command line, working directory) are cached against the
/// process start time, so a long-lived server is inspected once rather than on
/// every one-second refresh, while a restarted process on the same PID is
/// re-read automatically.
public final class ProcessInspector: @unchecked Sendable {
    private struct CacheEntry {
        var startedAt: Date?
        var details: ProcessDetails
    }

    private var cache: [pid_t: CacheEntry] = [:]
    private let lock = NSLock()

    public func details(for pid: pid_t) -> ProcessDetails {
        let start = startTime(of: pid)

        lock.lock()
        if let cached = cache[pid], cached.startedAt == start {
            lock.unlock()
            return cached.details
        }
        lock.unlock()

        let details = readDetails(for: pid, startedAt: start)

        lock.lock()
        cache[pid] = CacheEntry(startedAt: start, details: details)
        // Drop entries for processes that are gone so the cache can't grow
        // without bound during a long session.
        let live = Set(LibprocScanner.allPids())
        cache = cache.filter { live.contains($0.key) }
        lock.unlock()

        return details
    }

    public func invalidate() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    // MARK: - Fields

    private func readDetails(for pid: pid_t, startedAt: Date?) -> ProcessDetails {
        let path = executablePath(of: pid)
        let args = arguments(of: pid, executablePath: path)
        let name = processName(of: pid, path: path, arguments: args)
        return ProcessDetails(
            pid: pid,
            name: name,
            executablePath: path,
            arguments: args,
            workingDirectory: workingDirectory(of: pid),
            parentPID: parentPID(of: pid),
            startedAt: startedAt,
            appBundlePath: bundlePath(in: path)
        )
    }

    func processName(of pid: pid_t, path: String?, arguments: [String]) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        if length > 0 {
            let name = String(cString: buffer)
            if !name.isEmpty { return name }
        }
        if let path { return (path as NSString).lastPathComponent }
        if let first = arguments.first { return (first as NSString).lastPathComponent }
        return "pid \(pid)"
    }

    func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let path = String(cString: buffer)
        return path.isEmpty ? nil : path
    }

    /// Full argv, read from the `KERN_PROCARGS2` sysctl blob.
    ///
    /// Layout: `int argc`, the executable path, NUL padding, then `argc`
    /// NUL-terminated arguments followed by environment strings. Anything after
    /// the arguments is the environment, which we deliberately drop: it
    /// routinely contains API keys and tokens that have no business being
    /// displayed or logged.
    func arguments(of pid: pid_t, executablePath: String?) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size >= MemoryLayout<Int32>.size else {
            return []
        }

        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc > 0, argc < 4096 else { return [] }

        var index = MemoryLayout<Int32>.size
        // Skip the executable path.
        while index < size, buffer[index] != 0 { index += 1 }
        // Skip the NUL padding that aligns the argument block.
        while index < size, buffer[index] == 0 { index += 1 }

        var arguments: [String] = []
        while index < size, arguments.count < Int(argc) {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            let bytes = buffer[start..<index]
            if bytes.isEmpty {
                // An empty argument is legal; only a run of NULs after the last
                // argument means we have reached the environment block.
                if arguments.count >= Int(argc) { break }
                arguments.append("")
            } else {
                arguments.append(String(decoding: bytes, as: UTF8.self))
            }
            index += 1
        }
        // The kernel's argc and the argument block can disagree by a few NULs
        // for processes that rewrite their own argv (redis does). Trailing empty
        // strings are always padding, never a real argument.
        while arguments.last?.isEmpty == true { arguments.removeLast() }
        if arguments.isEmpty, let executablePath { return [executablePath] }
        return arguments
    }

    func workingDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = proc_pidinfo(
            pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(MemoryLayout<proc_vnodepathinfo>.size)
        )
        guard size == MemoryLayout<proc_vnodepathinfo>.size else { return nil }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        return path.isEmpty || path == "/" ? nil : path
    }

    func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard size == MemoryLayout<proc_bsdinfo>.size else { return nil }
        let parent = pid_t(info.pbi_ppid)
        return parent > 1 ? parent : nil
    }

    func startTime(of pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard size == MemoryLayout<proc_bsdinfo>.size, info.pbi_start_tvsec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))
    }

    /// Walks up from the executable to the nearest enclosing `.app` bundle.
    func bundlePath(in executablePath: String?) -> String? {
        guard let executablePath else { return nil }
        let components = (executablePath as NSString).pathComponents
        guard let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        let bundle = NSString.path(withComponents: Array(components[...appIndex]))
        return bundle == "/" ? nil : bundle
    }
}
