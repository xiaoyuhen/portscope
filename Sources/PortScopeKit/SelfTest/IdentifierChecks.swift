import Foundation

enum IdentifierChecks {
    static var all: [(String, () throws -> Void)] {
        [
            ("Django is recognised from manage.py", {
                let info = identify(process("python3", ["python3", "manage.py", "runserver"], port: 8000))
                try expectEqual(info.title, "Django", "title")
                try expect(info.confidence >= 0.9, "confidence was \(info.confidence)")
            }),
            ("Vite is recognised from the binary name", {
                let info = identify(process("node", ["node", "/w/app/node_modules/.bin/vite"], port: 5173))
                try expectEqual(info.title, "Vite", "title")
                try expectEqual(info.kind, .devServer, "kind")
            }),
            ("Redis is recognised even though it rewrites its own argv", {
                // redis-server replaces argv[0] with "redis-server 127.0.0.1:6379".
                let details = process(
                    "redis-server",
                    ["/cache/redis-server 127.0.0.1:6379"],
                    port: 6379,
                    executable: "/cache/redis-server"
                )
                let info = identify(details)
                try expectEqual(info.title, "Redis", "title")
                try expectEqual(info.kind, .cache, "kind")
            }),
            ("Express wins over the generic Node runtime", {
                let probe = HTTPProbeResult(
                    status: 404,
                    headers: ["x-powered-by": "Express"],
                    bodyPrefix: "",
                    spokeHTTP: true
                )
                let info = identify(process("node", ["node", "server.js"], port: 3000), probe: probe)
                try expectEqual(info.title, "Express", "title")
                try expect(info.confidence > 0.8, "confidence was \(info.confidence)")
            }),
            ("an unrecognised HTTP port says HTTP API, not unknown", {
                let probe = HTTPProbeResult(
                    status: 200,
                    headers: ["content-type": "application/json"],
                    bodyPrefix: "{}",
                    spokeHTTP: true
                )
                let info = identify(process("mystery-binary", ["mystery-binary"], port: 9999), probe: probe)
                try expectEqual(info.title, L10nKey.httpAPI, "title")
                try expectEqual(info.kind, .api, "kind")
            }),
            ("a silent process on a well-known port is a low-confidence guess", {
                let info = identify(process("mystery-binary", ["mystery-binary"], port: 5173))
                try expectEqual(info.title, "Vite", "title")
                try expect(info.confidence <= 0.5,
                           "a port-only guess must not look certain, got \(info.confidence)")
            }),
            ("nothing known at all yields Unknown service", {
                let info = identify(process("mystery-binary", ["mystery-binary"], port: 49999))
                try expectEqual(info.title, L10nKey.unknownService, "title")
            }),
            ("the project is found by walking up to a manifest", {
                let root = try TempProject(manifests: ["package.json"])
                defer { root.cleanup() }
                let nested = (root.path as NSString).appendingPathComponent("src/server")
                try FileManager.default.createDirectory(
                    atPath: nested, withIntermediateDirectories: true
                )
                let info = identify(
                    process("node", ["node", "server.js"], port: 3000, cwd: nested)
                )
                try expectEqual(info.projectPath, root.path, "project path")
                try expectEqual(info.projectName, (root.path as NSString).lastPathComponent, "name")
            }),
            ("a system container path is not reported as a project", {
                let info = identify(process(
                    "WeChat", ["WeChat"], port: 14013,
                    cwd: "/Users/someone/Library/Containers/com.tencent.xinWeChat/Data"
                ))
                try expect(info.projectPath == nil, "expected no project, got \(info.projectPath ?? "nil")")
            }),
            ("the home folder is not a project", {
                let info = identify(process("limactl", ["limactl", "hostagent"], port: 61071, cwd: NSHomeDirectory()))
                try expect(info.projectName == nil, "expected no project, got \(info.projectName ?? "nil")")
            }),
            ("databases are never HTTP-probed", {
                let identifier = ServiceIdentifier()
                try expect(!identifier.shouldProbe(port: 6379, kind: .cache), "cache probed")
                try expect(!identifier.shouldProbe(port: 5432, kind: nil), "postgres probed")
                try expect(identifier.shouldProbe(port: 3000, kind: .devServer), "dev server skipped")
            }),
        ]
    }

    // MARK: - Helpers

    /// Fixtures carry the port in `parentPID` so the call sites stay short;
    /// this pulls it back out for the identifier.
    private static func identify(_ details: ProcessDetails, probe: HTTPProbeResult? = nil) -> ServiceInfo {
        ServiceIdentifier().identify(
            port: Int(details.parentPID ?? 0), details: details, probe: probe
        )
    }

    private static func process(
        _ name: String,
        _ arguments: [String],
        port: Int,
        cwd: String? = nil,
        executable: String? = nil
    ) -> ProcessDetails {
        ProcessDetails(
            pid: 4242,
            name: name,
            executablePath: executable ?? "/usr/local/bin/\(name)",
            arguments: arguments,
            workingDirectory: cwd,
            parentPID: pid_t(port),
            startedAt: Date().addingTimeInterval(-3600),
            appBundlePath: nil
        )
    }
}

/// A throwaway directory with optional manifest files, for project-detection
/// checks. Created under the system temp directory and removed afterwards.
private final class TempProject {
    let path: String

    init(manifests: [String]) throws {
        path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("portscope-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        for manifest in manifests {
            let file = (path as NSString).appendingPathComponent(manifest)
            FileManager.default.createFile(atPath: file, contents: Data("{}".utf8))
        }
    }

    func cleanup() { try? FileManager.default.removeItem(atPath: path) }
}
