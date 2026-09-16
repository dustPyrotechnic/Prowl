# 069.002 — Undo after the last tab of a worktree closes

## Context

The plan listed "undo while no terminal surface has keyboard focus" as a
non-goal because ⌘Z only entered through Ghostty's `undo` binding, which needs
a focused surface. After the last tab of a worktree closed in the sidebar view
the terminal area was empty and ⌘Z did nothing, although the tab's record was
retained and restorable. Ghostty.app covers the same case (its last window
closed) through the standard `UndoManager` chain, and onevcat asked for the
equivalent.

## What did not work

The first cut mirrored Ghostty: an `UndoManager` subclass bridged to the close
stack, returned from the main window delegate's `windowWillReturnUndoManager`.
A probe build showed the delegate method is never called: SwiftUI's default
Edit › Undo / Redo items (the `.undoRedo` command group) validate and act
through SwiftUI's own undo plumbing and do not consult `NSWindow.undoManager`,
so the item stayed disabled and ⌘Z did nothing. Replacing the command group
would have taken ⌘Z away from text fields.

## Change

- `supacode/App/TerminalCloseUndoKeyMonitor.swift` — a local `keyDown` monitor
  bound to its owning window (`decision(for:ownerWindow:shortcuts:)` rejects
  events of any other window; a Settings or Diff window never drives the main
  window's stack). It routes Ghostty's default `undo` / `redo` triggers (⌘Z,
  ⌘⇧T, ⌘⇧Z) plus whatever `GhosttyShortcutManager.keyboardShortcut(for:)`
  resolves — additively, because `ghostty_config_trigger` hides `performable`
  bindings (the defaults are) and keeps one trigger per action — to
  `WorktreeTerminalManager.undoClose()` / `redoClose()`, and swallows the event
  only when something was restored or re-closed. It passes the key through when
  the first responder is a `GhosttySurfaceView` (Ghostty's binding handles it)
  or an `NSText` field editor (standard text undo). A `performable:` rebinding
  or an unbind of `undo` is invisible to this route (Review Loop round 1, R2).
- `supacode/App/WindowTabbingDisabler.swift` — the main window's helper view
  owns the monitor; `ContentView` supplies the triggers and the manager
  closures. The monitor is re-created only when the triggers change.
- Tests: `supacodeTests/TerminalCloseUndoKeyMonitorTests.swift` (routing for
  default and custom triggers, pass-through for text and terminal responders).

## Refs

#816.
