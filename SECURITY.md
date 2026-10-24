# Security

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.

Use GitHub's private reporting: **Security** tab → **Report a vulnerability**.
That opens a private advisory visible only to the maintainer.

If you cannot use that, email the address in the repository's commit metadata
with "PortScope security" in the subject.

Expect an acknowledgement within a few days. This is a single-maintainer
project, so please be patient — but a report about something that could harm
users will be prioritised over any feature work.

## What PortScope can and cannot do

Worth knowing before you assess an issue, because the app touches processes:

- **It runs as you, with your privileges.** No helper, no daemon, no root, no
  entitlements beyond what an ad-hoc-signed app gets.
- **It only signals processes you own.** `ProcessController` refuses anything
  whose UID is not yours, PID 1, and itself. A refusal is reported, not
  silently ignored.
- **It never reads your environment.** A restart replays argv through a login
  shell instead, because the environment block routinely holds API keys.
- **It connects only to loopback.** The HTTP prober connects to `127.0.0.1` and
  `::1`, never to a LAN address, even for a service bound to `0.0.0.0`. It
  sends `GET /` and reads a bounded number of bytes.
- **Telemetry sends no local data.** One event, once per version per day, with
  the app version and a random install ID. Never a port, process, path or
  hostname. See [docs/privacy.md](docs/privacy.md) and the switch in Settings.

## Scope

In scope: anything that lets another local user or a remote host influence what
PortScope does, any path where PortScope signals a process it does not own, any
data that leaves the machine beyond the documented telemetry event.

Out of scope: the app being able to stop your own processes (that is the
feature), and macOS Gatekeeper warnings on an ad-hoc-signed build (documented in
the README).
