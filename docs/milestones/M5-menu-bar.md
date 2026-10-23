# Milestone 5 — Menu bar presence

## Goal

PortScope should be visible without being in the way: a count in the menu bar,
and a compact list one click away.

## What it does

- **A live count** beside the icon — `▸▸ 17`. The whole point of a menu bar
  presence is answering "is anything running?" without opening a window.
- **A panel** listing every port, with the same service names and colours as
  the main window. Rows are clickable (open in browser); stop and restart
  appear on hover.
- **Closing the window no longer quits.** The app keeps running in the menu
  bar; "Open PortScope" brings the window back.

## Toolchain findings

Three SwiftUI/AppKit APIs do not work in this bundle configuration, and each
was replaced rather than worked around by the user:

| API | Result | Replacement |
|---|---|---|
| `MenuBarExtra` | no icon appears | `NSStatusItem` directly |
| `NSPopover` | handler fires, no panel shows | borderless `NSPanel` |
| `.sheet` | never presents | in-window overlay |

The `NSPopover` and `.sheet` failures look like the same root cause: modal
presentation needs a window scene this SwiftPM bundle does not get. A
non-activating `NSPanel` at `.statusBar` level presents correctly, and is
arguably the better shape for a menu bar utility anyway — it does not steal
focus and dismisses when you click away.

Two more details that mattered:

- **Activation policy.** With `.regular`, the status item is created
  (`isVisible == true`, correct frame) but never renders. `.accessory` makes it
  appear. That is the right policy for a background monitor regardless: no Dock
  icon, no app-switcher entry.
- **Observing the count.** A `NotificationCenter` observer registered with
  `name: nil` never fires for `@Published` changes. A Combine subscription to
  `store.$ports` is what keeps the number live.

## Layout

The panel's height is computed from the row height, not picked as a round
number:

```
visibleRows × (rowHeight + divider) + header + footer
```

A fixed 460pt panel showed a clipped half-row above the footer, which read as a
rendering bug. Ending on a whole row makes the panel look deliberate.

## Verification

Captured the status item at its measured accessibility position and confirmed
through `AXUIElement` that it is a real `AXMenuBarItem` with title " 17" and
size 61×24. The panel was captured as its own window (`NSWindow` layer 25) at
the expected anchor under the icon.
