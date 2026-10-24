# Privacy

PortScope is a tool for looking at your own machine. Almost everything it knows
stays there.

## What stays local, always

- **Every port, process and path it discovers.** Port numbers, PIDs, command
  lines, working directories, project names, HTTP headers and status codes are
  read and displayed, never transmitted.
- **Your preferences.** Language, refresh interval, hidden ports and the
  telemetry switch live in `~/Library/Preferences/io.github.xiaoyuhen.portscope.plist`.
- **Restart logs.** Output goes to `~/Library/Logs/PortScope/`.
- **Your shell environment.** It is never read: it routinely holds API keys.

## The one thing that leaves: an anonymous launch count

Open-source macOS apps have no download counter, so "is anyone using this?" is
otherwise unanswerable. PortScope sends one event, at most once per version per
day.

The complete payload:

```json
{
  "event": "launch",
  "app": "PortScope",
  "version": "0.2.0",
  "os": "14.5",
  "arch": "arm64",
  "id": "3F2A9C41-1B7E-4D2A-9F0C-8E5D6A7B2C31"
}
```

| Field | Why | What it is not |
|---|---|---|
| `version` | Which release people actually run | — |
| `os`, `arch` | Whether to keep supporting Intel | Major.minor only, never a build number |
| `id` | Distinguishes 1 person opening it 30 times from 30 people | A random UUID generated on first run. Not hardware, not your account, not your hostname |
| `app`, `event` | Route the request | Constants |

**Not sent, ever:** port numbers, process names, command lines, file paths,
project names, hostnames, usernames, IP-derived location, or anything about
what is listening.

The payload is built in one function (`Telemetry.payload`) from a fixed set of
fields, and the receiver drops any field not on its allowlist. Neither side can
quietly start collecting more.

## Turning it off

Any of these works:

1. **Settings → Anonymous launch count → off.** Takes effect immediately and
   stops any further send.
2. `defaults write io.github.xiaoyuhen.portscope PortScope.telemetry -bool NO`
3. Build without an endpoint: leave `PORTSCOPE_TELEMETRY_URL` unset and the app
   has nowhere to send.
4. `PORTSCOPE_NO_TELEMETRY=1` in the environment disables it at runtime.

Headless commands (`--selftest`, `--list`, `--stop`, `--restart`) never send
anything; only a normal app launch does.

## What the receiver stores

A daily aggregate, not a log:

```json
{
  "day": "2026-10-24",
  "launches": 12,
  "installs": { "<random uuid>": 1 },
  "versions": { "0.2.0": 11 },
  "platforms": { "14.5/arm64": 12 }
}
```

No IP address is read or written. The `installs` map holds random per-install
IDs and is used only to report distinct installs; it is not joined to anything
identifying. The worker source is in `infra/telemetry/worker.js` — it is short
enough to read in one sitting.

## If you build from source

A clone built with `./scripts/build.sh` has no telemetry endpoint baked in
unless you pass one, so a self-built copy sends nothing at all.
