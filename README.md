# PortScope

[简体中文](README.zh-CN.md) · English

A native macOS app that shows every port listening on your Mac, explains what
each service actually is, and lets you stop or restart it — without hunting
through `lsof`, `ps` and five terminal tabs.

> Status: in development. The milestones below are merged as they land.

## Why

`lsof -iTCP -sTCP:LISTEN` tells you a PID owns port 5173. It does not tell you
that it is a Vite dev server for the project in `~/work/acme-web`, that it is
bound to every network interface, or that it has been running for three days.
PortScope answers those questions at a glance.

## Planned features

- **Every listening port**, refreshed live — loopback, LAN and wildcard binds,
  with IPv4 and IPv6 de-duplicated into one row.
- **What it is**, not just which PID — service kind, project directory,
  framework, HTTP server header, and the evidence behind each guess.
- **Stop, force-stop and restart** a service, with a confirmation step for
  anything that is not a dev server.
- **Menu bar presence** — a count of live ports and the last few changes.
- **English and 简体中文**, switchable at runtime.
- **One-click open** in the browser, or copy `localhost:port`.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Command Line Tools — **Xcode is not required**

```bash
xcode-select --install   # if you don't have it
```

## Build and run

```bash
git clone git@github.com:xiaoyuhen/portscope.git
cd portscope
./scripts/build.sh          # debug
open dist/PortScope.app

./scripts/build.sh --release   # optimized
```

Self-checks (no test framework needed):

```bash
swift run PortScope --selftest
```

## Milestones

| # | Milestone | Status |
|---|-----------|--------|
| M0 | Foundation: package layout, app bundle, build script, i18n plumbing, self-test harness | ✅ |
| M1 | Native port scanner (libproc) with process attribution | ⬜ |
| M2 | Service identification: what each port is for | ⬜ |
| M3 | Main window UI | ⬜ |
| M4 | Stop / restart a service | ⬜ |
| M5 | Menu bar app, language switch, settings | ⬜ |
| M6 | Compatibility matrix, packaging, docs | ⬜ |

Each milestone lands as its own pull request; see `docs/milestones/`.

## Architecture

```
Sources/
  PortScopeKit/          # Engine, no UI. Reusable by a CLI or widget later.
    Core/                # Models, process runner, localization support
    SelfTest/            # Built-in checks, run with --selftest
  PortScope/             # SwiftUI app
    App/                 # Entry point, app-level state
    UI/                  # Design tokens and views
```

The engine is a plain Swift library so it can be tested and reused without a
window server. The app target only does presentation.

### Toolchain notes

PortScope builds with Apple's Command Line Tools alone. Two consequences are
baked into the code, and both are deliberate:

1. **No `@State` / `@Environment`.** Those are macros in current SDKs, and the
   `SwiftUIMacros` plugin is only installed with Xcode. Views use
   `ObservableObject` + `@StateObject` / `@EnvironmentObject`, which are real
   property wrappers and work everywhere.
2. **No XCTest, no Swift Testing.** CLT ships neither in a usable form, so
   checks live in `PortScopeKit/SelfTest` and run via `PortScope --selftest`.
   CI runs the same entry point.

## License

MIT
