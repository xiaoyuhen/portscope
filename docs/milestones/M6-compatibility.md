# Milestone 6 — Compatibility, packaging, docs

## Goal

Prove the app is right on real servers, not just on fixtures, and make it
installable.

## Compatibility matrix

`scripts/compat/run.sh` starts real projects from this machine, checks what
PortScope reports, then stops each through PortScope and confirms the port is
free. Five cases, all passing:

| Case | Reported as | Confidence |
|---|---|---|
| Express rate-limiter (+ ephemeral Redis child) | Express | 85% |
| Vite dev server | Vite | 95% |
| Python `http.server` | Python http.server | 95% |
| Framework-less Node server | Node.js | 55% |
| Express BFF in a monorepo | Express | 85% |

The interesting cases are the last two. The framework-less server is reported
as "Node.js, 55%" rather than an invented answer — being honestly unsure is a
feature. The monorepo runs two services from one repo; a naive scanner calls
both "node" and cannot tell them apart.

Details and instructions for adding cases: `docs/compatibility.md`.

### Bugs the matrix found

- The rate-limiter case used `npm start`, which needs an external Redis. The
  demo uses `npm run dev`, which starts an ephemeral one — and that child is
  exactly what the stop path must clean up.
- The monorepo server hardcodes its port in source, so `PORT=…` was ignored.
- `setsid` does not exist on macOS; process cleanup uses `pgrep -P` recursion.
- macOS ships bash 3.2, which has no `${var,,}` lowercase expansion.

## Packaging

`scripts/package.sh` produces a release build, verifies that both localizations
are inside the bundle (a missing `zh-Hans.lproj` would silently fall back to
English), zips with `ditto` to preserve the bundle structure, and prints a
SHA-256.

The app is ad-hoc signed. It runs on this machine; on another Mac it needs
right-click → Open the first time, or `xattr -dr com.apple.quarantine`. Proper
notarisation needs a Developer ID, which is out of scope for a local tool.

## Docs

- `README.md` / `README.zh-CN.md` — feature summary, identification model,
  safety rules, toolchain notes, milestones. English is the default, Chinese is
  linked from the top.
- `docs/milestones/` — one write-up per milestone, including the decisions and
  the defects that review caught.
- `docs/screenshots/` — dark and light captures of the ports list, overview,
  menu bar panel and confirmation dialog.
