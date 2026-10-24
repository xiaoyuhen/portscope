import AppKit
import Combine
import CryptoKit
import Foundation
import PortScopeKit

/// Checks GitHub for a newer release and installs it in place.
///
/// The shape follows what people expect from a Mac app updater: a check at
/// launch and once a day, a window that says what changed, and three answers —
/// install, remind me later, skip this version. Installing downloads the zip
/// and its checksum from the release, refuses anything that does not match,
/// swaps the bundle once PortScope has quit, and opens the new one.
///
/// A download made by the app is not quarantined, so the update opens without
/// the Gatekeeper prompt a browser download would get. That is also why it is
/// verified before it is installed: the checksum must match the file published
/// beside it, the bundle must be PortScope with the advertised version, and
/// its signature must be intact.
@MainActor
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(AvailableRelease)
        case downloading
        case installing
        case failed(String)
    }

    static let shared = Updater()

    @Published private(set) var state: State = .idle
    /// The release that is newer than this copy, whatever else is happening.
    /// The menu bar and Settings show it even after the window was dismissed.
    @Published private(set) var pending: AvailableRelease?
    @Published var checksAutomatically: Bool {
        didSet {
            defaults.set(checksAutomatically, forKey: Self.autoKey)
            schedule()
        }
    }

    /// Asked to show the release window. The app delegate owns the window.
    var presentWindow: (() -> Void)?

    private static let autoKey = "PortScope.update.automatic"
    private static let skippedKey = "PortScope.update.skippedVersion"
    private static let interval: TimeInterval = 24 * 60 * 60
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    /// "Remind me later" lasts until the next scheduled check.
    private var snoozed: String?

    private init() {
        LegacyPreferences.migrateIfNeeded()
        checksAutomatically = defaults.object(forKey: Self.autoKey) as? Bool ?? true
    }

    var currentVersion: String { AppDelegate.version }

    /// Starts the schedule: a first check shortly after launch, so it never
    /// competes with the first scan, then once a day.
    func start() {
        schedule()
        guard checksAutomatically else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            Task { await self?.check(userInitiated: false) }
        }
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard checksAutomatically else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.snoozed = nil
                await self?.check(userInitiated: false)
            }
        }
        timer.tolerance = 60 * 60
        self.timer = timer
    }

    /// One check. A user-initiated check always reports its result and shows
    /// a skipped version again; an automatic one stays silent unless there is
    /// something new the user has not declined.
    func check(userInitiated: Bool) async {
        if case .downloading = state { return }
        if case .installing = state { return }
        state = .checking
        var request = URLRequest(url: UpdateFeed.latestURL)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PortScope/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let release = UpdateFeed.parse(data) else {
                state = userInitiated ? .failed(AppLocale.shared.t("update.error.feed")) : .idle
                return
            }
            guard UpdateFeed.isNewer(release.version, than: currentVersion) else {
                pending = nil
                state = userInitiated ? .upToDate : .idle
                return
            }
            pending = release
            state = .available(release)
            let declined = defaults.string(forKey: Self.skippedKey) == release.version
                || snoozed == release.version
            if userInitiated || !declined {
                presentWindow?()
            }
        } catch {
            state = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    func skip(_ release: AvailableRelease) {
        defaults.set(release.version, forKey: Self.skippedKey)
        state = .idle
    }

    func remindLater(_ release: AvailableRelease) {
        snoozed = release.version
        state = .idle
    }

    // MARK: - Installing

    /// Downloads, verifies and installs `release`, then relaunches. Falls back
    /// to opening the release page when this copy cannot be replaced in place
    /// (a read-only location, or a translocated copy run from a download).
    func install(_ release: AvailableRelease) async {
        let target = Bundle.main.bundleURL
        guard canReplace(target) else {
            NSWorkspace.shared.open(release.pageURL)
            state = .failed(AppLocale.shared.t("update.error.location"))
            return
        }
        state = .downloading
        do {
            let staged = try await download(release)
            state = .installing
            try replaceAndRelaunch(target: target, with: staged)
        } catch {
            state = .failed((error as? UpdateError).map { AppLocale.shared.t($0.key) }
                ?? error.localizedDescription)
        }
    }

    /// A localization key; resolved when shown, on the main actor.
    struct UpdateError: Error {
        var key: String
        init(_ key: String) { self.key = key }
    }

    private func canReplace(_ bundle: URL) -> Bool {
        let path = bundle.path
        // App Translocation runs a quarantined download from a random
        // read-only mount; replacing that copy would update nothing.
        guard !path.contains("/AppTranslocation/") else { return false }
        return FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path)
            && FileManager.default.isWritableFile(atPath: path)
    }

    /// Fetches the zip and its checksum, verifies both, and unpacks the app
    /// into a fresh temporary folder. Returns the unpacked bundle.
    private func download(_ release: AvailableRelease) async throws -> URL {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("portscope-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let (sumData, sumResponse) = try await URLSession.shared.data(from: release.checksumURL)
        let (zipFile, zipResponse) = try await URLSession.shared.download(from: release.zipURL)
        // Redirects are followed to GitHub's asset storage; wherever they end
        // must still be GitHub.
        for response in [sumResponse, zipResponse] {
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let url = response.url, UpdateFeed.isTrusted(url) else {
                throw UpdateError("update.error.download")
            }
        }

        let zipName = "PortScope-\(release.version).zip"
        guard let expected = UpdateFeed.digest(
            fromChecksumFile: String(decoding: sumData, as: UTF8.self), zipName: zipName
        ) else { throw UpdateError("update.error.checksum") }
        let zip = work.appendingPathComponent(zipName)
        try FileManager.default.moveItem(at: zipFile, to: zip)
        let actual = SHA256.hash(data: try Data(contentsOf: zip, options: .mappedIfSafe))
            .map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw UpdateError("update.error.checksum") }

        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
        let app = unpacked.appendingPathComponent("PortScope.app")
        guard let info = Bundle(url: app)?.infoDictionary,
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == release.version else {
            throw UpdateError("update.error.bundle")
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        return app
    }

    /// Swaps the bundle after PortScope exits and opens the new one.
    ///
    /// The swap runs in a detached shell because a running app cannot replace
    /// itself. Paths are passed as arguments, never spliced into the script.
    /// The old bundle is moved aside first and moved back if the new one
    /// cannot be put in place, so a failed update leaves the old app working.
    private func replaceAndRelaunch(target: URL, with staged: URL) throws {
        let backup = target.deletingLastPathComponent()
            .appendingPathComponent(".PortScope-previous-\(UUID().uuidString).app")
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        if mv "$2" "$4"; then
            if mv "$3" "$2"; then
                rm -rf "$4"
            else
                mv "$4" "$2"
            fi
        fi
        open "$2"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "portscope-update",
                             String(getpid()), target.path, staged.path, backup.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        NSApp.terminate(nil)
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError("update.error.bundle") }
    }
}
