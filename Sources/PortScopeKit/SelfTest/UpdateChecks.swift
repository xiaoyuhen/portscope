import Foundation

/// Checks for the update feed. An updater that misreads a version installs the
/// wrong thing, and one that trusts the wrong host installs someone else's.
enum UpdateChecks {
    static func release(tag: String = "v0.3.0", host: String = "github.com",
                        prerelease: Bool = false, assetVersion: String? = nil) -> Data {
        let version = assetVersion ?? (tag.hasPrefix("v") ? String(tag.dropFirst()) : tag)
        let base = "https://\(host)/xiaoyuhen/portscope/releases/download/\(tag)"
        return Data("""
        {"tag_name": "\(tag)", "name": "PortScope \(version)", "body": "Fixes.",
         "html_url": "https://github.com/xiaoyuhen/portscope/releases/tag/\(tag)",
         "draft": false, "prerelease": \(prerelease),
         "assets": [
           {"name": "PortScope-\(version).zip", "browser_download_url": "\(base)/PortScope-\(version).zip"},
           {"name": "PortScope-\(version).zip.sha256", "browser_download_url": "\(base)/PortScope-\(version).zip.sha256"}
         ]}
        """.utf8)
    }

    static var all: [(String, () throws -> Void)] {
        [
            ("versions compare numerically, not as text", {
                try expect(UpdateFeed.isNewer("0.10.0", than: "0.9.9"), "0.10.0 > 0.9.9")
                try expect(UpdateFeed.isNewer("0.3.0", than: "0.2.2"), "0.3.0 > 0.2.2")
                try expect(!UpdateFeed.isNewer("0.2.2", than: "0.2.2"), "equal is not newer")
                try expect(!UpdateFeed.isNewer("0.3", than: "0.3.0"), "0.3 == 0.3.0")
                try expect(!UpdateFeed.isNewer("0.2.1", than: "0.2.2"), "older is not newer")
                try expect(!UpdateFeed.isNewer("garbage", than: "0.2.2"), "garbage is not newer")
            }),
            ("a published release with both assets is read", {
                let parsed = UpdateFeed.parse(release())
                try expectEqual(parsed?.version, "0.3.0", "version")
                try expectEqual(parsed?.zipURL.lastPathComponent, "PortScope-0.3.0.zip", "zip")
                try expectEqual(parsed?.checksumURL.lastPathComponent, "PortScope-0.3.0.zip.sha256", "sum")
            }),
            ("a prerelease is never offered", {
                try expect(UpdateFeed.parse(release(prerelease: true)) == nil, "prerelease offered")
            }),
            ("assets outside GitHub are refused", {
                try expect(UpdateFeed.parse(release(host: "example.com")) == nil, "foreign host accepted")
            }),
            ("assets for another version are refused", {
                try expect(UpdateFeed.parse(release(assetVersion: "0.2.2")) == nil,
                           "a release whose zip is another version was accepted")
            }),
            ("a checksum must name the zip it vouches for", {
                let hex = String(repeating: "ab", count: 32)
                try expectEqual(UpdateFeed.digest(fromChecksumFile: "\(hex)  PortScope-0.3.0.zip\n",
                                                  zipName: "PortScope-0.3.0.zip"), hex, "match")
                try expect(UpdateFeed.digest(fromChecksumFile: "\(hex)  Other.zip\n",
                                             zipName: "PortScope-0.3.0.zip") == nil, "wrong name")
                try expect(UpdateFeed.digest(fromChecksumFile: "abc  PortScope-0.3.0.zip\n",
                                             zipName: "PortScope-0.3.0.zip") == nil, "short digest")
            }),
        ]
    }
}
