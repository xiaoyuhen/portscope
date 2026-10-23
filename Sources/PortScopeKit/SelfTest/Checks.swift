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
            ("preferred language is always supported", {
                try expect(
                    LocalizationSupport.supportedLanguages.contains(
                        LocalizationSupport.preferredLanguage()),
                    "preferred language not in the supported list"
                )
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
