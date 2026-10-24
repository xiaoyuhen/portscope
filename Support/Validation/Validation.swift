import AppKit
import ApplicationServices

/// Drives the running PortScope app the way a person would and checks what
/// actually appears on screen.
///
/// The self-tests cover the logic, but every bug reported so far lived outside
/// it: a panel that listed rows the window folded, a button that opened
/// nothing, a default language taken from the system. Those are lifecycle and
/// rendering facts, and the only honest way to check them is to press the
/// buttons and read the screen.
///
/// Usage:
///   scripts/validate.sh              # full run
///   scripts/validate.sh --keep       # leave the app running afterwards
///
/// It launches a scratch copy of the built app with an isolated preferences
/// domain, so a run never touches the real settings, and it kills only the
/// process it started.
@main
enum Validation {
    static func main() {
        let args = CommandLine.arguments
        let bundlePath = args.count > 1 && !args[1].hasPrefix("--")
            ? args[1]
            : "dist/PortScope.app"
        let keep = args.contains("--keep")

        let harness = Harness(bundlePath: bundlePath)
        do {
            try harness.runAll()
        } catch {
            print("\n\(harness.report)")
            print("FAILED: \(error)")
            harness.stop()
            exit(1)
        }
        print("\n\(harness.report)")
        if !keep { harness.stop() }
        exit(harness.failures == 0 ? 0 : 1)
    }
}

// MARK: - Harness

final class Harness {
    private let bundlePath: String
    private var app: NSRunningApplication?
    private var pid: pid_t = 0
    private var scratchDomain = ""

    private(set) var passed = 0
    private(set) var failures = 0
    private var lines: [String] = []

    init(bundlePath: String) {
        self.bundlePath = bundlePath
    }

    var report: String { lines.joined(separator: "\n") }

    // MARK: Checks

    func runAll() throws {
        guard AXIsProcessTrusted() else {
            throw Failure("this terminal needs Accessibility permission to drive the UI "
                          + "(System Settings › Privacy & Security › Accessibility)")
        }
        let url = URL(fileURLWithPath: bundlePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Failure("no app bundle at \(bundlePath) — run scripts/build.sh first")
        }

        try launch(freshPreferences: true)
        try checkFirstLaunchIsEnglish()
        try checkWindowOpensOnLaunch()
        try checkMenuBarItemExists()
        try checkPanelFoldsBackgroundPorts()
        try checkPanelDisclosureMatchesWindow()
        try checkOpenPortScopeFromPanel()
        try checkWindowReopensAfterClose()
        try checkQuitIsTheOnlyWayOut()

        try relaunchWithStoredChinese()
        try checkStoredChineseIsHonoured()
    }

    // MARK: Lifecycle

    private func launch(freshPreferences: Bool) throws {
        scratchDomain = "io.github.xiaoyuhen.portscope.validation.\(getpid())"
        if freshPreferences { wipeScratchPreferences() }
        // Copy the bundle so the run cannot disturb an installed copy, and give
        // it a bundle identifier of its own so preferences stay isolated.
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("portscope-validation-\(getpid())/PortScope.app")
        try? FileManager.default.removeItem(at: scratch.deletingLastPathComponent())
        try FileManager.default.createDirectory(
            at: scratch.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: URL(fileURLWithPath: bundlePath), to: scratch)
        try rewriteBundleIdentifier(of: scratch)

        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = true
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var launched: NSRunningApplication?
        nonisolated(unsafe) var launchError: Error?
        NSWorkspace.shared.openApplication(at: scratch, configuration: config) { app, error in
            launched = app
            launchError = error
            semaphore.signal()
        }
        semaphore.wait()
        if let launchError { throw Failure("could not launch: \(launchError)") }
        guard let launched else { throw Failure("launch returned no application") }
        app = launched
        pid = launched.processIdentifier

        // Wait for the first scan to finish. The window exists immediately but
        // is empty until then, and every later check depends on real rows.
        let deadline = Date().addingTimeInterval(20)
        var scanned = false
        var lastText = ""
        while Date() < deadline {
            let text = windowTexts().joined(separator: " ")
            if !text.isEmpty { lastText = text }
            if let total = totalPorts(in: text), total > 0 {
                scanned = true
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard scanned else {
            throw Failure(undriveableReason(lastText: lastText))
        }
        // Let identification and the HTTP probes settle, so the panel is judged
        // on finished data rather than on a half-filled list.
        Thread.sleep(forTimeInterval: 1.5)
    }

    /// Why the app could not be driven, in the terms the person running it can
    /// act on.
    ///
    /// A full-screen app elsewhere on the system moves other apps' windows to
    /// another Space, where Accessibility cannot see them. The symptom is a
    /// running app with zero readable windows, which otherwise looks exactly
    /// like a broken window. It is not, and saying so saves a debugging session.
    private func undriveableReason(lastText: String) -> String {
        let windows = windowCount()
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        if windows == 0 {
            return "the app is running but Accessibility sees no windows for it. "
                + "That is what a full-screen app elsewhere on the system looks like "
                + "(frontmost: \(front)). Leave full screen and re-run."
        }
        if lastText.isEmpty {
            return "the window is present but rendered no text. "
                + "The app may be on another Space (frontmost: \(front))."
        }
        return "the first scan produced no ports; the machine should have some "
            + "(saw: \(lastText))"
    }

    /// Parses the footer's total from either language: "6 of 21 ports" or
    /// "6 / 20 个端口". The harness reads the same strings the user does, so it
    /// has to understand both.
    private func totalPorts(in text: String) -> Int? {
        let patterns = [#"\d+ of (\d+) ports"#, #"\d+ / (\d+) 个端口"#]
        for pattern in patterns {
            guard let match = text.range(of: pattern, options: .regularExpression)
            else { continue }
            // "6 of 21 ports" / "6 / 20 个端口" — the number is the third field.
            let fields = text[match].split(separator: " ")
            if fields.count >= 3, let value = Int(fields[2]) { return value }
        }
        return nil
    }

    private func rewriteBundleIdentifier(of bundle: URL) throws {
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              var root = try PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil) as? [String: Any] else {
            throw Failure("could not read \(plist.path)")
        }
        root["CFBundleIdentifier"] = scratchDomain
        let rewritten = try PropertyListSerialization.data(
            fromPropertyList: root, format: .xml, options: 0)
        try rewritten.write(to: plist)
        // Replacing Info.plist breaks the signature; an ad-hoc re-sign keeps
        // macOS willing to launch it.
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", bundle.path]
        sign.standardError = FileHandle.nullDevice
        sign.standardOutput = FileHandle.nullDevice
        try? sign.run()
        sign.waitUntilExit()
    }

    private func wipeScratchPreferences() {
        let defaults = Process()
        defaults.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        defaults.arguments = ["delete", scratchDomain]
        defaults.standardError = FileHandle.nullDevice
        defaults.standardOutput = FileHandle.nullDevice
        try? defaults.run()
        defaults.waitUntilExit()
    }

    func stop() {
        guard let app else { return }
        app.terminate()
        let deadline = Date().addingTimeInterval(5)
        while !app.isTerminated && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if !app.isTerminated { app.forceTerminate() }
        // The scratch copy exists only for this run.
        try? FileManager.default.removeItem(
            atPath: NSTemporaryDirectory() + "portscope-validation-\(getpid())")
        try? FileManager.default.removeItem(
            atPath: NSHomeDirectory() + "/Library/Preferences/\(scratchDomain).plist")
    }

    private func relaunchWithStoredChinese() throws {
        stop()
        scratchDomain = "io.github.xiaoyuhen.portscope.validation.\(getpid())"
        let defaults = Process()
        defaults.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        defaults.arguments = ["write", scratchDomain, "PortScope.language", "zh-Hans"]
        try? defaults.run()
        defaults.waitUntilExit()
        try launch(freshPreferences: false)
    }

    // MARK: Checks — first launch

    private func checkFirstLaunchIsEnglish() throws {
        // The system may well be Chinese; the app must still open in English.
        let topBar = windowTexts().joined(separator: " ")
        try check("first launch is English",
                  topBar.contains("Ports") && topBar.contains("Settings"),
                  detail: "saw: \(topBar)")
        try check("first launch is not Chinese",
                  !topBar.contains("端口") && !topBar.contains("设置"),
                  detail: "saw: \(topBar)")
    }

    private func checkWindowOpensOnLaunch() throws {
        let count = windowCount()
        try check("the main window opens on launch", count == 1,
                  detail: "found \(count) windows")
        let size = windowFrame()?.size ?? .zero
        try check("the window has a usable size",
                  size.width >= 800 && size.height >= 500,
                  detail: "\(Int(size.width))x\(Int(size.height))")
    }

    private func checkMenuBarItemExists() throws {
        try check("a menu bar item exists", !statusItems().isEmpty)
    }

    // MARK: Checks — panel parity

    private func checkPanelFoldsBackgroundPorts() throws {
        try openPanel()
        let text = panelTexts().joined(separator: " ")
        try check("the panel renders rows", !text.isEmpty)

        // Whatever the window folded must be folded here too. The check is not
        // "WeChat is hidden" — it is "the two surfaces agree", which is the
        // property that actually broke.
        let window = windowTexts().joined(separator: " ")
        let windowFolded = window.contains("desktop and system ports")
        let panelFolded = text.contains("desktop and system ports")
        try check("the panel and the window agree about folding",
                  windowFolded == panelFolded,
                  detail: "window folded: \(windowFolded), panel folded: \(panelFolded)")

        // The specific apps that were reported inline. They may legitimately
        // appear when expanded, so only assert while the section is folded.
        if panelFolded {
            for noise in ["WeChat", "ControlCenter", "Discord"] {
                try check("\(noise) is folded out of the panel", !text.contains(noise),
                          detail: "listed inline while the section is folded")
            }
        }
        closePanel()
    }

    private func checkPanelDisclosureMatchesWindow() throws {
        try openPanel()
        let panel = panelTexts().joined(separator: " ")
        closePanel()
        guard let panelCount = foldedCount(in: panel) else {
            lines.append("  --  folded count: the panel has nothing folded to compare")
            return
        }
        guard let windowCount = foldedCount(in: windowTexts().joined(separator: " ")) else {
            lines.append("  --  folded count: the window has nothing folded to compare")
            return
        }
        try checkEqual("the panel and the window fold the same number of ports",
                       panelCount, windowCount)
    }

    /// Parses "12 desktop and system ports" into 12.
    private func foldedCount(in text: String) -> Int? {
        guard let range = text.range(of: #"(\d+) desktop and system ports"#,
                                     options: .regularExpression) else { return nil }
        return Int(text[range].split(separator: " ").first ?? "")
    }

    // MARK: Checks — the reported bug

    private func checkOpenPortScopeFromPanel() throws {
        // The bug: with the main window closed, "Open PortScope" did nothing.
        // Close the window first, so the button has to do real work.
        try closeWindow()
        try checkEqual("closing the window leaves no window open", windowCount(), 0)

        try openPanel()
        guard let button = findButton(titled: "Open PortScope") else {
            closePanel()
            throw Failure("no 'Open PortScope' button in the panel")
        }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 1.5)

        try check("Open PortScope reopens the window", windowCount() >= 1)
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        try check("the reopened window comes to the front", frontmost,
                  detail: "frontmost app is "
                    + "\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "none")")
    }

    private func checkWindowReopensAfterClose() throws {
        try closeWindow()
        try checkEqual("closing the window leaves no window open", windowCount(), 0)
        // Reopening twice must work: the window is hidden, not destroyed, and a
        // second open has to find it again.
        try openFromPanel()
        try check("the window reopens the first time", windowCount() >= 1)
        try closeWindow()
        try openFromPanel()
        try check("the window reopens a second time", windowCount() >= 1)
    }

    private func checkQuitIsTheOnlyWayOut() throws {
        try closeWindow()
        Thread.sleep(forTimeInterval: 1.0)
        try check("closing the window does not quit the app", app?.isTerminated == false)
    }

    // MARK: Checks — language

    private func checkStoredChineseIsHonoured() throws {
        let text = windowTexts().joined(separator: " ")
        try check("a stored Chinese preference renders Chinese",
                  text.contains("端口"), detail: "saw: \(text)")
        try check("a stored Chinese preference leaves no English labels",
                  !text.contains("Live"), detail: "saw: \(text)")
    }

    // MARK: AX helpers

    private func appElement() -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    private func windows() -> [String] {
        axWindows().map { collectText($0).joined(separator: " ") }
    }

    private func windowTexts() -> [String] { windows() }

    private func windowCount() -> Int { axWindows().count }

    private func axWindows() -> [AXUIElement] {
        attribute(appElement(), kAXWindowsAttribute) as? [AXUIElement] ?? []
    }

    private func windowFrame() -> CGRect? {
        guard let window = axWindows().first else { return nil }
        var size = CGSize.zero
        if let value = attribute(window, kAXSizeAttribute) {
            AXValueGetValue(value as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: .zero, size: size)
    }

    private func statusItems() -> [AXUIElement] {
        guard let bar = attribute(appElement(), kAXExtrasMenuBarAttribute) else { return [] }
        return attribute(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    /// The panel is an NSPanel, so it shows up in the app's window list with a
    /// different size from the main window.
    private func panelWindow() -> AXUIElement? {
        axWindows().first { window in
            var size = CGSize.zero
            if let value = attribute(window, kAXSizeAttribute) {
                AXValueGetValue(value as! AXValue, .cgSize, &size)
            }
            return size.width <= 400 && size.height <= 500
        }
    }

    private func panelTexts() -> [String] {
        guard let panel = panelWindow() else { return [] }
        return collectText(panel)
    }

    /// Opens the panel if it is not already open.
    ///
    /// Pressing the status item *toggles*, so a helper that always presses is
    /// only correct if it knows the current state. It waits for the panel to
    /// appear and presses again if the first press closed it instead — the
    /// panel can be dismissed by the system between checks.
    private func openPanel() throws {
        guard let item = statusItems().first else { throw Failure("no status item") }
        for _ in 0..<3 {
            if panelWindow() != nil { return }
            AXUIElementPerformAction(item, kAXPressAction as CFString)
            Thread.sleep(forTimeInterval: 1.0)
        }
        guard panelWindow() != nil else {
            throw Failure("panel did not open after three presses")
        }
    }

    private func closePanel() {
        guard let item = statusItems().first else { return }
        for _ in 0..<3 {
            guard panelWindow() != nil else { return }
            AXUIElementPerformAction(item, kAXPressAction as CFString)
            Thread.sleep(forTimeInterval: 0.6)
        }
    }

    private func closeWindow() throws {
        guard let window = axWindows().first(where: { $0 !== panelWindow() }) else { return }
        guard let button = attribute(window, kAXCloseButtonAttribute) else {
            throw Failure("the main window has no close button")
        }
        AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func openFromPanel() throws {
        try openPanel()
        guard let button = findButton(titled: "Open PortScope") else {
            closePanel()
            throw Failure("no 'Open PortScope' button in the panel")
        }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 1.2)
    }

    private func findButton(titled title: String) -> AXUIElement? {
        guard let panel = panelWindow() else { return nil }
        return find(in: panel) { element in
            guard let role = attribute(element, kAXRoleAttribute) as? String,
                  role == kAXButtonRole as String else { return false }
            let value = attribute(element, kAXTitleAttribute) as? String
                ?? attribute(element, kAXDescriptionAttribute) as? String
                ?? attribute(element, kAXValueAttribute) as? String
            return value == title
        }
    }

    private func find(in element: AXUIElement, _ match: (AXUIElement) -> Bool,
                      depth: Int = 0) -> AXUIElement? {
        if match(element) { return element }
        guard depth < 30 else { return nil }
        for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            if let found = find(in: child, match, depth: depth + 1) { return found }
        }
        return nil
    }

    private func collectText(_ element: AXUIElement, depth: Int = 0) -> [String] {
        guard depth < 30 else { return [] }
        var out: [String] = []
        let role = attribute(element, kAXRoleAttribute) as? String
        if role == kAXStaticTextRole as String || role == kAXButtonRole as String {
            for key in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
                if let text = attribute(element, key) as? String, !text.isEmpty {
                    out.append(text)
                }
            }
        }
        for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            out += collectText(child, depth: depth + 1)
        }
        return out
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return value
    }

    // MARK: Assertions

    /// `label` describes what should be true, so a pass and a failure can both
    /// be read without decoding a negated message.
    private func check(_ label: String, _ condition: Bool,
                       detail: @autoclosure () -> String = "") throws {
        if condition {
            passed += 1
            lines.append("[  ok  ] \(label)")
        } else {
            failures += 1
            let extra = detail()
            lines.append("[ FAIL ] \(label)" + (extra.isEmpty ? "" : " — \(extra)"))
            throw Failure(label + (extra.isEmpty ? "" : " — \(extra)"))
        }
    }

    private func checkEqual<T: Equatable>(_ label: String, _ actual: T, _ expected: T) throws {
        try check(label, actual == expected, detail: "expected \(expected), got \(actual)")
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
