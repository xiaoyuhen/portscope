# Milestone 0 — Foundation

## Goal

A repository that builds, launches and reports its own health on a machine with
only Apple Command Line Tools installed. No feature work yet.

## Delivered

- **Package layout** — `PortScopeKit` (engine library) and `PortScope`
  (SwiftUI app). The split exists so the scanner and classifier can be tested
  and later reused by a CLI without a window server.
- **App bundle pipeline** — `scripts/build.sh` compiles the SwiftPM product,
  wraps it in `PortScope.app` with `Info.plist`, copies localizations and
  ad-hoc signs it. `xcodebuild` and Xcode are not used.
- **Localization plumbing** — `en` and `zh-Hans` string tables, a runtime
  language switch stored in UserDefaults, and a lookup that falls back to
  English and then to the key itself so a missing translation is visible.
- **Self-test harness** — `PortScope --selftest` runs checks in the library and
  exits non-zero on failure. This replaces XCTest, which Command Line Tools do
  not ship.
- **CI** — build, self-test, bundle and bundle verification on `macos-14`.

## Decisions worth remembering

**No `@State` / `@Environment`.** In the current SDK these are macros backed by
the `SwiftUIMacros` plugin, which ships only with Xcode. `@StateObject`,
`@EnvironmentObject`, `@Observable` and `@AppStorage` are ordinary property
wrappers and work fine. Views therefore own state through `ObservableObject`.

**Self-test instead of XCTest.** `XCTest` is absent from CLT, and Swift
Testing's macro plugin is absent too. Rather than require Xcode, the checks are
plain functions in the library, invoked from the app binary. This also gives CI
a single command that works identically for a contributor and for the runner.

**Ad-hoc signing.** `codesign --sign -` is enough for local use and for CI
verification. Developer ID signing is only needed to move the app to another
machine; that is deferred to M6.

## Verification

```
$ swift run PortScope --selftest
[  ok  ] every supported language has a native display name
[  ok  ] English is the fallback language
[  ok  ] preferred language is always supported
[  ok  ] localURL prefers a concrete loopback address
[  ok  ] localURL brackets IPv6 addresses
[  ok  ] exposure marks wildcard binds as reachable

6 passed, 0 failed
```

The app launches, shows its window with the correct canvas colour, and
`CFBundleLocalizations` lists both languages.
