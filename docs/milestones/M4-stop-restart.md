# Milestone 4 — Stop and restart

## Goal

Stop or restart a service from the list, without `kill -9` and a guessed PID.

## Rules

This is the only part of the app that changes the machine, so three rules are
enforced in code rather than trusted to the UI:

1. **Never signal what we do not own.** Only processes owned by the current
   user; never PID 1; never PortScope itself. A port monitor that can kill
   arbitrary system services is a liability. Refusals are returned as values
   and explained in the UI ("the process belongs to another user"), not
   swallowed.
2. **SIGTERM first, SIGKILL only after a grace period.** Services get three
   seconds to clean up. If SIGKILL was needed, the UI says so — "it did not
   exit cleanly" is information the user should have.
3. **Take the children.** A dev server owns its children: a compiler, a Redis,
   a watcher. Killing only the port owner orphans them, and they keep the port
   busy, so the restart fails with `EADDRINUSE`. Descendants are collected from
   the kernel's parent table and signalled children-first.

## Confirmation

Always confirmed, but a single click — not a type-the-name ritual. The dialog
adds the context that makes the decision easy: service, port, PID, uptime, and
for a restart, the exact command that will be replayed. Desktop and system
processes get an extra warning, because stopping `ControlCenter` closes the
AirPlay receiver.

It is an in-window overlay rather than a sheet: the list stays visible behind
it, and it keeps the decision visually attached to the row it came from.

## Restart

The original argv is replayed through a login shell (`zsh -lc`), so the process
inherits the user's PATH — a `node` started from an nvm-managed shell does not
exist for a process that only inherits PortScope's environment. Arguments are
single-quoted, so an argument containing `;` or `$(...)` cannot escape into a
second command.

The original environment is **not** restored. PortScope deliberately never
reads it (it holds API keys and tokens), so a restart gets the shell's
environment. This is documented in the confirmation dialog's help text rather
than left as a surprise.

Restart is verified, not assumed: the port must come back listening within 20
seconds, otherwise the action is reported as failed. Output goes to
`~/Library/Logs/PortScope/port-<port>.log` so a service that dies on startup
can be diagnosed instead of vanishing.

## Command line

`PortScope --stop <port>` and `PortScope --restart <port>` use the same
controller. They make the destructive paths testable end-to-end without
clicking, and they are the obvious thing to reach from a script.

## Verification

Nine checks cover the dangerous parts:

- PortScope refuses to signal itself and launchd.
- A missing PID is reported as gone, not as success.
- A child process is found among the descendants.
- Stopping a real spawned child terminates it and reports success.
- Quoting survives `;`, `'` and spaces.
- A restart command replays argv, with a fallback to the executable path.

End-to-end, against the rate-limiter project on :3000:

```
$ PortScope --restart 3000
restarted on port 3000 as pid 40464        # new PID, port listening, HTTP 404 as before
$ PortScope --stop 3000
stopped node (pid 40464) on port 3000      # port free afterwards
```

And through the UI: confirmation → Stop → "Stopped Express." → the row and its
port disappear on the next refresh.

## Notes

SwiftUI `.sheet` and `.overlay` both silently failed to present in this bundle
configuration while the app's own root content rendered correctly. The
confirmation is therefore an overlay applied *after* `.environmentObject`, and
the cause is documented in `RootView.swift` — the overlay subtree must be able
to read the store.
