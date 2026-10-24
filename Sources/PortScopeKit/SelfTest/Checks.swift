import Foundation

enum LocalizationChecks {
    static var all: [(String, () throws -> Void)] {
        [
            ("every supported language has a native display name", {
                for language in LocalizationSupport.supportedLanguages {
                    try expect(!LocalizationSupport.displayName(for: language).isEmpty,
                               "empty display name for \(language)")
                }
            }),
            ("English is the fallback language", {
                try expectEqual(LocalizationSupport.supportedLanguages.first, "en", "fallback")
            }),
            ("a fresh install starts in English", {
                // The system locale must not decide this: on a Chinese Mac the
                // app still opens in English until Chinese is chosen.
                try expectEqual(LocalizationSupport.resolve(stored: nil), "en", "unset")
                try expectEqual(LocalizationSupport.resolve(stored: ""), "en", "empty")
            }),
            ("an explicit choice is honoured", {
                try expectEqual(LocalizationSupport.resolve(stored: "zh-Hans"), "zh-Hans", "chosen")
            }),
            ("an unknown stored language falls back to English", {
                try expectEqual(LocalizationSupport.resolve(stored: "fr"), "en", "unknown")
                try expectEqual(LocalizationSupport.resolve(stored: "zh-Hant"), "en", "unsupported")
            }),
        ]
    }
}

enum PortInfoChecks {
    static var all: [(String, () throws -> Void)] {
        [
            ("localURL prefers a concrete loopback address", {
                let info = makePort(addresses: ["0.0.0.0", "127.0.0.1"], port: 3000)
                try expectEqual(info.localURL?.absoluteString, "http://127.0.0.1:3000", "url")
            }),
            ("localURL brackets IPv6 hosts", {
                let info = makePort(addresses: ["::1"], port: 5173)
                try expectEqual(info.localURL?.absoluteString, "http://localhost:5173", "url")
            }),
            ("exposure marks wildcard binds as reachable", {
                try expect(Exposure.allInterfaces.isPubliclyReachable, "wildcard should be reachable")
                try expect(!Exposure.loopback.isPubliclyReachable, "loopback should not be reachable")
            }),
        ]
    }

    private static func makePort(addresses: [String], port: Int) -> PortInfo {
        PortInfo(
            port: port,
            addresses: addresses,
            exposure: .loopback,
            pid: 1,
            processName: "node",
            executablePath: "/usr/bin/node",
            arguments: ["node", "server.js"],
            workingDirectory: nil,
            uptime: 10,
            appBundleName: nil,
            service: nil
        )
    }
}

/// Ensures the two shipped string tables contain the same keys.
///
/// A missing translation is not a crash — the lookup falls back to English —
/// but it is a defect, and one that is invisible unless someone reads the
/// Chinese UI. This check makes drift fail the build instead.
enum ResourceChecks {
    static var all: [(String, () throws -> Void)] {
        [
            ("every English string has a Chinese translation", {
                let (english, chinese) = try loadTables()
                let missing = Set(english).subtracting(Set(chinese)).sorted()
                try expect(missing.isEmpty, "missing zh-Hans keys: \(missing.joined(separator: ", "))")
            }),
            ("every Chinese string exists in English", {
                let (english, chinese) = try loadTables()
                let extra = Set(chinese).subtracting(Set(english)).sorted()
                try expect(extra.isEmpty, "keys only in zh-Hans: \(extra.joined(separator: ", "))")
            }),
            ("every service fingerprint has a summary string", {
                let (english, _) = try loadTables()
                let referenced = Set(ServiceCatalog.processFingerprints.map(\.match.summaryKey)
                    + ServiceCatalog.httpFingerprints.map(\.match.summaryKey)
                    + ServiceCatalog.portFingerprints.map(\.match.summaryKey))
                let missing = referenced.subtracting(Set(english)).sorted()
                try expect(missing.isEmpty, "missing summary keys: \(missing.joined(separator: ", "))")
            }),
        ]
    }

    /// Parses the `.strings` files directly from the source tree. The harness
    /// runs before the app bundle exists, so it reads the same files the bundle
    /// is built from rather than going through `Bundle`.
    private static func loadTables() throws -> (english: [String], chinese: [String]) {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SelfTest
            .deletingLastPathComponent()   // PortScopeKit
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // repo root
        let resources = root
            .appendingPathComponent("Sources/PortScope/Resources")
        return (
            try keys(in: resources.appendingPathComponent("en.lproj/Localizable.strings")),
            try keys(in: resources.appendingPathComponent("zh-Hans.lproj/Localizable.strings"))
        )
    }

    /// Keys are the quoted token before `=`. Values are ignored; a malformed
    /// line is skipped rather than failing the parse, so one bad entry shows up
    /// as a missing key with a clear message.
    private static func keys(in url: URL) throws -> [String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\""), let equals = trimmed.range(of: "\" =") else { return nil }
            return String(trimmed[trimmed.startIndex..<equals.lowerBound].dropFirst())
        }
    }
}

/// Checks for the foreground/background split the list uses to fold desktop
/// and system ports away.
///
/// The rule is a judgement, so it is tested rather than trusted: folding the
/// wrong row means a service someone started is invisible by default.
enum BackgroundClassificationChecks {
    static var all: [(String, () async throws -> Void)] {
        [
            ("a system service is folded", {
                try expect(
                    BackgroundClassification.isBackground(port(kind: .system, bundle: nil)),
                    "system service should fold"
                )
            }),
            ("a chat client is folded", {
                try expect(
                    BackgroundClassification.isBackground(port(kind: .messaging, bundle: "WeChat")),
                    "chat client should fold"
                )
            }),
            ("an app-bundle process is folded", {
                try expect(
                    BackgroundClassification.isBackground(port(kind: .web, bundle: "SomeApp")),
                    "app bundle should fold"
                )
            }),
            ("a dev server is never folded, even from an app bundle", {
                try expect(
                    !BackgroundClassification.isBackground(port(kind: .devServer, bundle: "SomeApp")),
                    "dev server must stay visible"
                )
            }),
            ("a database is never folded", {
                try expect(
                    !BackgroundClassification.isBackground(port(kind: .database, bundle: nil)),
                    "database must stay visible"
                )
            }),
            ("a plain Node process is never folded", {
                try expect(
                    !BackgroundClassification.isBackground(port(kind: .web, bundle: nil)),
                    "node server must stay visible"
                )
            }),
            // The point of the rule is that it generalises. An app nobody has
            // heard of must fold without being added to any list.
            ("an unknown chat app is folded without being named", {
                try expect(
                    BackgroundClassification.isBackground(
                        port(kind: .messaging, bundle: "SomeNewChatApp")),
                    "unnamed app must fold"
                )
            }),
            ("an Apple daemon in a system directory is folded", {
                try expect(
                    BackgroundClassification.isBackground(
                        port(kind: .other, bundle: nil, executable: "/usr/libexec/rapportd")),
                    "system daemon must fold"
                )
            }),
            ("a developer runtime in a system directory stays visible", {
                // python3 lives in /usr/bin; the executable check has to win
                // over the system-path check, or `python3 -m http.server`
                // would disappear into the folded section.
                try expect(
                    !BackgroundClassification.isBackground(
                        port(kind: .web, bundle: nil, executable: "/usr/bin/python3")),
                    "python server must stay visible"
                )
            }),
            ("a versioned runtime is recognised", {
                try expect(
                    !BackgroundClassification.isBackground(
                        port(kind: .web, bundle: nil, executable: "/opt/homebrew/bin/python3.12")),
                    "python3.12 must stay visible"
                )
            }),
            ("a process in a project directory stays visible", {
                try expect(
                    !BackgroundClassification.isBackground(
                        port(kind: .web, bundle: nil, executable: "/opt/homebrew/bin/rails",
                             projectPath: "/Users/x/app")),
                    "project process must stay visible"
                )
            }),
            ("an unidentified process is not hidden", {
                // Folding what we cannot explain would hide the one row the
                // user most wants to see.
                try expect(
                    !BackgroundClassification.isBackground(
                        port(kind: .other, bundle: nil, executable: "/opt/homebrew/bin/mystery")),
                    "unknown binary must stay visible"
                )
            }),
            ("a developer app bundle stays visible", {
                // Docker's listener is `com.docker.backend`, which the runtime
                // list recognises before the bundle rule can fold it.
                try expect(
                    !BackgroundClassification.isBackground(
                        port(kind: .container, bundle: "Docker Desktop",
                             executable: "/Applications/Docker.app/Contents/MacOS/com.docker.backend")),
                    "Docker backend must stay visible"
                )
            }),
            ("a developer app whose binary is not a runtime is still folded", {
                // VS Code holds a port for its own extension host. It is a GUI
                // app, not something the user started as a server, so it folds.
                try expect(
                    BackgroundClassification.isBackground(
                        port(kind: .web, bundle: "Visual Studio Code",
                             executable: "/Applications/Visual Studio Code.app/Contents/MacOS/Code Helper")),
                    "VS Code should fold"
                )
            }),
            ("a third-party app with no category is folded", {
                // magpie declares no LSApplicationCategoryType; the rule cannot
                // depend on metadata an app may omit.
                try expect(
                    BackgroundClassification.isBackground(
                        port(kind: .api, bundle: "magpie",
                             executable: "/Applications/magpie.app/Contents/MacOS/magpie")),
                    "magpie should fold"
                )
            }),
        ]
    }

    private static func port(
        kind: ServiceInfo.Kind,
        bundle: String?,
        executable: String = "/x",
        projectPath: String? = nil
    ) -> PortInfo {
        PortInfo(
            port: 4000, addresses: ["127.0.0.1"], exposure: .loopback,
            pid: 99, processName: "proc", executablePath: executable,
            arguments: [], workingDirectory: nil, uptime: 1,
            appBundleName: bundle,
            service: ServiceInfo(
                kind: kind, title: "t", summaryKey: "s", confidence: 0.9,
                evidence: [], httpStatus: nil, serverHeader: nil,
                projectPath: projectPath, projectName: nil
            )
        )
    }
}

/// The window and the menu bar panel draw `PortListModel.rows`. These checks
/// pin the behaviour both of them depend on — the surfaces can only stay in
/// agreement if the rows they are handed are right.
enum PortListModelChecks {
    static var all: [(String, () async throws -> Void)] {
        [
            ("background ports are folded behind a disclosure", {
                let rows = PortListModel.rows(
                    foreground: [port(3000)], background: [port(5000), port(5001)],
                    backgroundExpanded: false, searching: false
                )
                try expectEqual(rows.count, 2, "one port plus the disclosure")
                try expect(rows.first == .port(port(3000), muted: false), "foreground first")
                try expect(rows.last == .backgroundDisclosure(count: 2), "disclosure last")
            }),
            ("an expanded list has no disclosure row", {
                let rows = PortListModel.rows(
                    foreground: [port(3000)], background: [port(5000)],
                    backgroundExpanded: true, searching: false
                )
                try expectEqual(rows.count, 2, "both ports")
                try expect(rows.last == .port(port(5000), muted: true), "background is muted")
            }),
            ("a search shows background matches while folded", {
                let rows = PortListModel.rows(
                    foreground: [], background: [port(14013)],
                    backgroundExpanded: false, searching: true
                )
                try expectEqual(rows.count, 1, "the match")
                try expect(rows.first == .port(port(14013), muted: true), "muted match")
            }),
            ("no disclosure is offered when nothing is folded", {
                let rows = PortListModel.rows(
                    foreground: [port(3000)], background: [],
                    backgroundExpanded: false, searching: false
                )
                try expectEqual(rows.count, 1, "just the port")
            }),
            ("row ids are unique", {
                let rows = PortListModel.rows(
                    foreground: [port(3000), port(4000)], background: [port(5000)],
                    backgroundExpanded: true, searching: false
                )
                try expectEqual(Set(rows.map(\.id)).count, rows.count, "duplicate row id")
            }),
        ]
    }

    private static func port(_ number: Int) -> PortInfo {
        PortInfo(
            port: number, addresses: ["127.0.0.1"], exposure: .loopback,
            pid: 99, processName: "proc", executablePath: "/x",
            arguments: [], workingDirectory: nil, uptime: 1,
            appBundleName: nil, service: nil
        )
    }
}
