# PortScope

[简体中文](README.zh-CN.md) · English

A native macOS app that shows every port listening on your Mac, explains what
each service actually is, and lets you stop or restart it — without hunting
through `lsof`, `ps` and five terminal tabs.

![PortScope](docs/screenshots/ports-dark.png)

## Why

`lsof -iTCP -sTCP:LISTEN` tells you a PID owns port 5173. It does not tell you
that it is a Vite dev server for the project in `~/work/acme-web`, that it is
bound to every network interface, or that it has been running for three days.
PortScope answers those questions at a glance, and shows its reasoning.

## What it does

- **Every listening port, live.** Loopback, LAN and wildcard binds; IPv4 and
  IPv6 sockets of one service collapsed into a single row. A full scan takes
  about 100 ms and needs no elevated privileges.
- **What it is, not just which PID.** Service, framework, project directory,
  HTTP status, and the evidence behind each conclusion. When it is unsure it
  says so — "Node.js, 55%" rather than a confident guess.
- **Stop and restart.** Confirmed first, children included, verified after. See
  [Safety](#safety) for exactly what it will and will not touch.
- **A menu bar count.** Closing the window leaves PortScope running in the menu
  bar with a live port count.
- **English and 简体中文**, switchable at runtime.
- **Open in browser** or copy `localhost:port` from any row.

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
./scripts/package.sh           # zipped, checksummed release build
```

## Command line

The same engine, without the window — useful for scripts, and how the
compatibility suite drives it.

```bash
PortScope --list            # table of ports, processes and services
PortScope --list --json     # machine-readable
PortScope --stop 3000       # stop the service on :3000
PortScope --restart 3000    # stop it, then replay its command line
PortScope --selftest        # built-in checks, exit code 1 on failure
```

## How identification works

Three tiers of evidence, strongest first. They are merged rather than replaced:
a lower tier that *agrees* raises confidence, one that is merely present does
not.

| Tier | Signal | Example |
|---|---|---|
| 1. Process | executable, argv, cwd | `manage.py runserver` → Django, 95% |
| 2. HTTP | headers from a loopback-only `GET /` | `Server: AirTunes` → AirPlay receiver |
| 3. Port | well-known ports, last resort | 5173 → Vite, **capped at 50%** |

Confidence is capped at 99%: every signal here is inference. A port that
answers HTTP but matches nothing is reported as "HTTP API" at 35%, not as
"unknown" — that something is serving HTTP is already useful.

The probe is deliberately narrow: `127.0.0.1` only (never the LAN address, even
for a service bound to `0.0.0.0`), 1.5 s timeout, fixed User-Agent, no proxy,
and skipped entirely for ports that cannot speak HTTP.

## Safety

PortScope changes your machine, so the rules are enforced in code:

- **Never signals what it does not own** — only your own processes, never PID 1,
  never itself. Refusals are explained in the UI.
- **SIGTERM first**, SIGKILL only after a three-second grace period — and the UI
  says when force-kill was needed.
- **Takes the children.** A dev server owns its compiler, database and watcher;
  killing only the port owner leaves them holding the port.
- **Never reads your environment.** It is where API keys live, so a restart gets
  your shell's environment instead — noted in the confirmation dialog.
- **Verifies restarts.** The port must listen again within 20 s or the action is
  reported as failed. Output goes to `~/Library/Logs/PortScope/`.

## Compatibility

`scripts/compat/run.sh` starts real servers from this machine, checks that
PortScope identifies each one correctly, then stops it through PortScope and
confirms the port is free. Current matrix: the Express rate-limiter, a Vite dev
server, Python's `http.server`, a framework-less Node server, and an Express +
Vite monorepo. See [docs/compatibility.md](docs/compatibility.md).

## Architecture

```
Sources/
  PortScopeKit/          # Engine, no UI. Reusable by a CLI or widget.
    Core/                # Scanner, process inspector, identifier, controller
    SelfTest/            # Built-in checks, run with --selftest
  PortScope/             # SwiftUI app
    App/                 # Entry point, store, menu bar, CLI commands
    UI/                  # Design tokens and views
```

### Toolchain notes

PortScope builds with Apple's Command Line Tools alone. Several SDK gaps are
worked around explicitly, and each is documented where it bites:

- `@State` / `@Environment` are macros whose plugin ships only with Xcode →
  `LocalState<Value>` (a one-property `ObservableObject`) for view-local state.
- Neither XCTest nor Swift Testing is usable from CLT → checks live in
  `PortScopeKit/SelfTest` and run via `--selftest`.
- `MenuBarExtra` and `NSPopover` do not present in this bundle configuration →
  `NSStatusItem` and a borderless `NSPanel`.
- SwiftUI `.sheet` never presents → in-window confirmation overlay.

## Milestones

| # | Milestone | Status |
|---|-----------|--------|
| M0 | Foundation: package layout, app bundle, build script, i18n, self-test | ✅ |
| M1 | Native port scanning (libproc) with process attribution | ✅ |
| M2 | Service identification: what each port is for | ✅ |
| M3 | Main window | ✅ |
| M4 | Stop and restart a service | ✅ |
| M5 | Menu bar app, language switch, settings | ✅ |
| M6 | Compatibility matrix, packaging, docs | ✅ |

Each landed as its own pull request; the write-ups are in `docs/milestones/`.

## License

MIT
