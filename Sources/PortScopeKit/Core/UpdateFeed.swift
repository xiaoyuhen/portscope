import Foundation

/// A published release, as much of it as an update needs.
public struct AvailableRelease: Sendable, Equatable {
    public var version: String
    public var title: String
    /// The release notes, Markdown, as written in the tag message.
    public var notes: String
    public var pageURL: URL
    public var zipURL: URL
    public var checksumURL: URL
}

/// Reads GitHub's "latest release" for this repository.
///
/// The feed is the GitHub Releases API rather than an appcast: releases are
/// already published there by the release workflow, so there is no second
/// file to keep in step, and nothing to host.
public enum UpdateFeed {
    public static let latestURL = URL(string: "https://api.github.com/repos/xiaoyuhen/portscope/releases/latest")!

    /// Hosts a download may come from. GitHub serves release assets from
    /// github.com and redirects to its object storage.
    static let assetHosts: Set<String> = [
        "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com",
    ]

    /// Parses the API response. Nil for anything that is not a usable,
    /// published release with both the zip and its checksum attached.
    public static func parse(_ data: Data) -> AvailableRelease? {
        struct Asset: Decodable { var name: String; var browser_download_url: String }
        struct Release: Decodable {
            var tag_name: String
            var name: String?
            var body: String?
            var html_url: String
            var draft: Bool?
            var prerelease: Bool?
            var assets: [Asset]
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              release.draft != true, release.prerelease != true else { return nil }
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        guard components(version) != nil,
              let page = URL(string: release.html_url),
              let zip = release.assets.first(where: { $0.name == "PortScope-\(version).zip" }),
              let sum = release.assets.first(where: { $0.name == "PortScope-\(version).zip.sha256" }),
              let zipURL = URL(string: zip.browser_download_url), isTrusted(zipURL),
              let sumURL = URL(string: sum.browser_download_url), isTrusted(sumURL) else { return nil }
        return AvailableRelease(
            version: version,
            title: release.name ?? "PortScope \(version)",
            notes: release.body ?? "",
            pageURL: page,
            zipURL: zipURL,
            checksumURL: sumURL
        )
    }

    /// HTTPS from GitHub only.
    public static func isTrusted(_ url: URL) -> Bool {
        url.scheme == "https" && assetHosts.contains(url.host ?? "")
    }

    /// True when `candidate` is a later version than `current`. Versions are
    /// dot-separated integers; a missing component counts as zero, so 0.3 and
    /// 0.3.0 are the same version.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let new = components(candidate), let old = components(current) else { return false }
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    static func components(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        return parts.map { $0! }
    }

    /// The digest from a `shasum -a 256` line: `<64 hex>  <filename>`. The
    /// filename must be the zip's, so a checksum file for another download
    /// cannot vouch for this one.
    public static func digest(fromChecksumFile text: String, zipName: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 2 else { continue }
            let hex = fields[0].lowercased()
            let name = fields[1].hasPrefix("*") ? String(fields[1].dropFirst()) : String(fields[1])
            if name == zipName, hex.count == 64, hex.allSatisfy(\.isHexDigit) {
                return hex
            }
        }
        return nil
    }
}
