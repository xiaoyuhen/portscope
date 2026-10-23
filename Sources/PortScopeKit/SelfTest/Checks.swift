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
