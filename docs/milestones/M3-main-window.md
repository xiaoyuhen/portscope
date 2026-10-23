# Milestone 3 — The window

## Goal

A window that answers the original question at a glance: which ports are
running, what each one is, and what to do about it.

## Design

The reference (magpie) is followed closely because its structure is exactly
right for this data:

- **Adaptive canvas.** Near-black in dark mode, near-white in light. Colours are
  dynamic `NSColor`s, so there is no per-view light/dark branching anywhere.
- **Centred pill navigation.** The nav sits in the middle of the window, not
  left-aligned after the logo, so it stays put as pages change.
- **One container, hairline rows.** Not a card per port. A list of cards reads
  as a set of unrelated things; one container reads as *the machine*.
- **Colour reserved for status.** The kind tints are muted; the only saturated
  colour in the list is the amber "On all interfaces" warning.
- **Small caps section labels** ("BY KIND", "ACTIVITY"), tracked out.

## Pages

### Ports

Filter chips with live counts, search, and a dense list. Each row: kind glyph,
service name, process · project, exposure warning (only when reachable from the
network), confidence, port, and open/copy actions on hover.

Selecting a row opens the **inspector** beside the list rather than replacing
it — the list stays readable while you investigate one port.

The inspector is built around the evidence:

```
WHY PORTSCOPE THINKS SO                    85% confident
▌ HTTP header    x-powered-by: Express
▌ Process        scripts/dev.js
```

A confident-sounding label with no visible basis would be worse than no label,
so the evidence is given as much space as the conclusion.

### Overview

Stat tiles, a kind breakdown (stacked bar + legend — the one visual where the
proportions are the point), the exposure panel, and an **activity log**.

The activity log answers a question the live list cannot: *something was on
8080 a minute ago — what was it?* Ports that come and go are exactly the ones
people need help identifying. Events keep the service name from the moment of
the change, because by the next scan the process is gone.

### Settings

Refresh interval, runtime language switch, hidden ports.

## Toolchain note

`@State` and `@Binding` are macros in the current SDK and unavailable without
Xcode. Views use `LocalState<Value>` — a one-property `ObservableObject` — for
view-local state, and explicit `Binding(get:set:)` where a control needs one.
Shared state lives in `PortStore`.

## Verification

Captured both themes and the empty-state path. Checks that drove fixes:

- Filter chips looked unselected because the fill was too close to the surface
  on a near-black canvas → added a border to the selected chip.
- `hostAndPort` printed `[::]:3000` → wildcard binds now show `localhost:3000`.
- "Dev servers: 0" while four dev servers ran → the tile counts web/API too,
  since a bare `node` identifies as `.web`.
