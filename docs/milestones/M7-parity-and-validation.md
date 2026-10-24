# M7 — Parity, defaults, and validation

A bug-report round rather than a feature milestone. Four defects, all in the
places the existing self-tests could not see, and the harness that closes that
gap.

## The four defects

### The menu bar panel disagreed with the window

The panel had its own filter:

```swift
private var developmentPorts: [PortInfo] {
    store.ports.filter { !store.hiddenPorts.contains($0.port) }
}
```

It applied the user's hidden list and nothing else. The main window had grown a
foreground/background split; the panel had not, so it listed WeChat,
ControlCenter and Discord inline while the window folded the same rows behind
"14 desktop and system ports".

Two surfaces computing the same thing will drift, and this one had. The fix is
not to copy the window's filter into the panel — it is to stop either surface
from filtering. `PortListModel.rows(foreground:background:backgroundExpanded:searching:)`
now returns the rows, and both surfaces render that array. They can still differ
in *how* a row is drawn (the popover has no search field and half the row
height); they cannot differ in *which rows exist*.

### The folding rule was a blocklist wearing a heuristic's clothes

The previous rule was:

```swift
switch info.service?.kind {
case .system: return true
case .messaging: return true
default: return info.appBundleName != nil
}
```

`.messaging` is a hardcoded category. Everything else in an app bundle folded,
which was closer to right, but the reported request was for a rule that
generalises rather than a longer list of app names.

Three candidate signals were measured against this machine before choosing:

| Signal | Verdict |
| --- | --- |
| `LSApplicationCategoryType` | Unusable. ChatGPT, Claude and WorkBuddy all declare `public.app-category.developer-tools`, while `magpie` declares nothing. |
| Parent process (`launchd` vs shell) | No signal. On modern macOS every process's parent is `launchd`, including ones started from a terminal. |
| Executable name | Works, and is the one thing that genuinely changes the answer. |

So the rule is structural, in this order:

1. Kind is a developer kind (`.devServer`, `.database`, `.container`, …) → show.
2. Executable is a developer runtime (`node`, `python3.12`, `redis-server`, …) → show.
3. The process has a project directory → show.
4. Kind is `.system` → fold.
5. Executable is under `/System/`, `/usr/libexec/`, … → fold.
6. It lives in a `.app` bundle → fold.
7. Otherwise → show.

The ordering is the design. Step 2 comes before step 5, so a
`python3 -m http.server` served by `/usr/bin/python3` stays visible; step 2
comes before step 6, so Docker's `com.docker.backend` listener stays visible.
Step 7 is the safe direction: an unidentified process is shown, because folding
the one row someone is looking for is the expensive mistake.

The remaining names are developer runtimes. That list only grows when a new
runtime appears, never when a new app does.

Measured on this machine: 6 visible, 14 folded — including Qoder, VS Code and
magpie, none of which appear in any list in the source.

### "Open PortScope" did nothing

SwiftUI destroys its `WindowGroup` window when it is closed. The old handler
looked for a window that could become main and ordered it front; after a close
there was no such window, so the button silently did nothing.

`MainWindowController` now owns the window:

- `windowShouldClose` returns `false` and calls `orderOut`, so closing hides.
- `show()` adopts SwiftUI's window on first use (keeping its scene styling),
  and builds one from `RootView` if it is ever gone.
- `applicationShouldHandleReopen` routes the Dock-icon path through the same
  method.

Verified by the harness closing the window and pressing the button twice.

### Everyone got their system language

`AppLocale.init` fell back to `LocalizationSupport.preferredLanguage()`, which
walks `Locale.preferredLanguages`. A Chinese macOS opened in Chinese on first
run.

`LocalizationSupport.resolve(stored:)` replaces it: English unless a stored,
supported language says otherwise. `preferredLanguage()` is gone, and the
`defaultLanguage` constant documents why — the vocabulary is developer
vocabulary, and the English terms are the ones people search for.

## The validation scheme

The self-tests are the wrong shape for these bugs. All four are window
lifecycle, rendering, or preference-resolution facts; none of them is visible to
a function that returns a value.

`scripts/validate.sh` drives the built app the way a person would:

1. Copy the bundle to a temp directory and rewrite `CFBundleIdentifier`, so the
   run has an isolated preferences domain and cannot touch real settings.
2. Re-sign ad hoc (the plist edit invalidates the signature).
3. Launch it, wait for the first scan to produce rows.
4. Read the window and the menu bar panel through Accessibility.
5. Close the window, open the panel, press "Open PortScope", read the screen.
6. Quit, relaunch with `PortScope.language = zh-Hans`, check it is Chinese.

Twenty checks, including the properties that actually broke:

- the panel and the window agree about folding;
- the folded count is the same on both surfaces;
- WeChat / ControlCenter / Discord are not inline while folded;
- the window reopens, twice, and is frontmost;
- closing the window does not quit;
- a fresh install is English; a stored Chinese preference is honoured.

### What it caught immediately

Writing the harness found two things the code review had not:

- The first version of `show()` was a no-op because `Validation.main()` was
  never called (`@main` needs `-parse-as-library` in a single-file build). A
  passing run that did nothing is worse than a failing one.
- A full-screen app elsewhere on the system makes **every other app's windows
  invisible to Accessibility** — `AXWindows` returns 0 while `AXMainWindow` still
  resolves and `CGWindowList` still lists the window. The harness now reports
  that condition explicitly instead of a blank "no ports" failure, because the
  symptom is otherwise indistinguishable from a broken window.

## Why CI compiles but does not run it

A GitHub macOS runner is a headless instance with no logged-in GUI session. The
harness would find no window and fail for a reason unrelated to any change. CI
compiles it (`swiftc -O -parse-as-library`) so it cannot rot, and the README
says to run it locally after touching the window, the menu bar or the language
path.

## Totals

- 56 logic checks (`PortScope --selftest`)
- 20 UI checks (`scripts/validate.sh`)
