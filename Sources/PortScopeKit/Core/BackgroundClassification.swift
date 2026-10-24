import Foundation

/// Decides which ports are folded away by default.
///
/// The audience is developers, and for a developer most listening ports belong
/// to something they did not start: a chat client, a browser helper, an Apple
/// daemon. Those rows are noise. But a hardcoded list of app names (WeChat,
/// Discord, …) is the wrong mechanism — it goes stale the moment someone
/// installs something new.
///
/// So the rule is structural rather than a list:
///
/// 1. **Work you started is always visible.** A developer runtime (node,
///    python, docker, redis, …) is foreground no matter where it lives.
/// 2. **A project working directory is always visible.** A process running
///    inside a directory with a manifest is something someone started here,
///    even if the binary is unusual.
/// 3. **System locations are background.** `/System/`, `/usr/libexec/`,
///    `/usr/sbin/` and friends are Apple's daemons.
/// 4. **GUI apps are background.** Anything launched from a `.app` bundle is an
///    app someone installed, not a service they run — which covers every chat
///    client, browser and utility without naming any of them. A developer app
///    that really does hold a port (Docker, OrbStack) still shows, because its
///    listener is a developer runtime checked at step 1, before the bundle
///    rule.
///
/// The result is that installing a new app never requires a code change. The
/// only names in this file are executables that mean "a developer is running
/// something" — a list that only has to grow when a new runtime appears, never
/// when a new app does. That is the difference between a rule and a blocklist.
public enum BackgroundClassification {
    /// Kinds that are always shown.
    public static let alwaysForeground: Set<ServiceInfo.Kind> = [
        .devServer, .bundler, .database, .cache, .ai, .container,
    ]

    /// Executables that mean "a developer is running something".
    ///
    /// Deliberately generous: a false positive here only means a row stays
    /// visible, which is the safe direction. The dangerous direction is folding
    /// a service someone started.
    public static let developerExecutables: Set<String> = [
        // Runtimes
        "node", "nodejs", "bun", "deno", "python", "python3", "python3.9",
        "python3.10", "python3.11", "python3.12", "python3.13", "ruby", "java",
        "go", "php", "dotnet", "mono", "elixir", "beam.smp", "erl", "swift",
        // Package / task runners
        "npm", "npx", "pnpm", "yarn", "corepack", "tsx", "ts-node", "nodemon",
        "vite", "next", "nuxt", "webpack", "webpack-dev-server", "uvicorn",
        "gunicorn", "flask", "manage.py", "rails", "puma", "mix", "air",
        // Containers
        "docker", "docker-compose", "com.docker.backend", "colima", "limactl",
        "podman", "qemu-system-aarch64", "orb", "orbstack",
        // Servers and data stores
        "nginx", "caddy", "httpd", "apache2", "redis-server", "valkey-server",
        "memcached", "postgres", "postmaster", "mysqld", "mongod", "clickhouse",
        "influxd", "elasticsearch", "qdrant", "ollama", "minio", "rabbitmq-server",
        "nats-server", "mosquitto", "consul", "vault", "kafka",
    ]

    /// Prefixes that mean "this belongs to macOS", not to the user.
    public static let systemPrefixes = [
        "/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/",
        "/Library/Apple/", "/System/Applications/",
    ]

    /// Whether a port belongs to something that runs in the background by
    /// nature. See the type comment for the ordering, which matters: "started
    /// by a developer" is checked before "lives in an app bundle", so Docker's
    /// backend and OrbStack's daemon stay visible.
    public static func isBackground(_ info: PortInfo) -> Bool {
        let kind = info.service?.kind
        if let kind, alwaysForeground.contains(kind) {
            return false
        }
        if let executable = info.executablePath, isDeveloperExecutable(executable) {
            return false
        }
        // A process working inside a project is something a person started,
        // whatever the binary is called.
        if info.service?.projectPath != nil {
            return false
        }
        // The identifier already recognised this as macOS infrastructure. That
        // is a judgement about the process, not a name in a list, so it folds
        // even when the path is somewhere unexpected.
        if kind == .system {
            return true
        }
        if let executable = info.executablePath,
           systemPrefixes.contains(where: { executable.hasPrefix($0) }) {
            return true
        }
        // Any other app-bundle process is an installed app. No name list: a new
        // chat client, a new browser, a new utility all fold without a code
        // change.
        if info.appBundleName != nil {
            return true
        }
        return false
    }

    static func isDeveloperExecutable(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if developerExecutables.contains(name) { return true }
        // `python3.12`, `ruby3.3`, … — strip a trailing version suffix.
        if let base = name.split(separator: ".").first.map(String.init),
           developerExecutables.contains(base) {
            return true
        }
        return false
    }
}
