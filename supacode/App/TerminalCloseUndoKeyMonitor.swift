import AppKit
import SwiftUI

/// Routes Ghostty's `undo` / `redo` keys to the close-undo stack when no
/// terminal surface can take them (docs-ai 069).
///
/// A focused terminal handles the keys itself through Ghostty's binding. After
/// the last tab of a worktree closes, the terminal area is empty and nothing
/// receives ⌘Z: SwiftUI's Edit › Undo does not consult the window's undo
/// manager, so a local key monitor is the one place the key can be caught.
/// The monitor answers only for its owning window; text editing keeps its own
/// undo: a field editor as first responder passes the key through untouched.
@MainActor
final class TerminalCloseUndoKeyMonitor {
  enum Route: Equatable {
    case undo
    case redo
    case pass
  }

  /// The triggers this route answers to. Ghostty's reverse lookup
  /// (`ghostty_config_trigger`) hides `performable` bindings, which the
  /// default undo/redo bindings are, and keeps one trigger per action, so a
  /// resolved trigger is treated as additive to the defaults rather than as a
  /// replacement. A `performable:` rebinding or an explicit unbind is not
  /// visible here.
  struct Shortcuts: Equatable {
    var undo: [KeyboardShortcut]
    var redo: [KeyboardShortcut]

    static let ghosttyDefaults = Shortcuts(
      undo: [
        KeyboardShortcut("z", modifiers: .command),
        KeyboardShortcut("t", modifiers: [.command, .shift]),
      ],
      redo: [KeyboardShortcut("z", modifiers: [.command, .shift])]
    )

    static func resolving(undo: KeyboardShortcut?, redo: KeyboardShortcut?) -> Shortcuts {
      var shortcuts = ghosttyDefaults
      if let undo, !shortcuts.undo.contains(undo) {
        shortcuts.undo.append(undo)
      }
      if let redo, !shortcuts.redo.contains(redo) {
        shortcuts.redo.append(redo)
      }
      return shortcuts
    }
  }

  private var monitor: Any?

  /// `ownerWindow` is resolved per event: the owning view may not be in a
  /// window yet when the monitor is installed.
  init(
    ownerWindow: @escaping @MainActor () -> NSWindow?,
    shortcuts: Shortcuts,
    undo: @escaping @MainActor () -> Bool,
    redo: @escaping @MainActor () -> Bool
  ) {
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let handled = MainActor.assumeIsolated { () -> Bool in
        switch Self.decision(for: event, ownerWindow: ownerWindow(), shortcuts: shortcuts) {
        case .undo: return undo()
        case .redo: return redo()
        case .pass: return false
        }
      }
      return handled ? nil : event
    }
  }

  isolated deinit {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
  }

  /// The full decision for one event: the event must belong to the owning
  /// window, whose first responder must not own undo itself.
  static func decision(for event: NSEvent, ownerWindow: NSWindow?, shortcuts: Shortcuts) -> Route {
    guard let ownerWindow, let eventWindow = event.window, eventWindow === ownerWindow else { return .pass }
    return route(
      characters: event.charactersIgnoringModifiers,
      modifierFlags: event.modifierFlags,
      firstResponderOwnsUndo: firstResponderOwnsUndo(ownerWindow.firstResponder),
      shortcuts: shortcuts
    )
  }

  /// A terminal answers the key through Ghostty's own binding; a text field
  /// keeps the standard text undo.
  nonisolated static func firstResponderOwnsUndo(_ responder: NSResponder?) -> Bool {
    responder is GhosttySurfaceView || responder is NSText
  }

  nonisolated static func route(
    characters: String?,
    modifierFlags: NSEvent.ModifierFlags,
    firstResponderOwnsUndo: Bool,
    shortcuts: Shortcuts
  ) -> Route {
    guard !firstResponderOwnsUndo, let characters, characters.count == 1 else { return .pass }
    let modifiers = eventModifiers(from: modifierFlags)
    if shortcuts.redo.contains(where: { matches($0, characters: characters, modifiers: modifiers) }) {
      return .redo
    }
    if shortcuts.undo.contains(where: { matches($0, characters: characters, modifiers: modifiers) }) {
      return .undo
    }
    return .pass
  }

  private nonisolated static func matches(
    _ shortcut: KeyboardShortcut,
    characters: String,
    modifiers: EventModifiers
  ) -> Bool {
    shortcut.modifiers == modifiers
      && String(shortcut.key.character).lowercased() == characters.lowercased()
  }

  private nonisolated static func eventModifiers(from flags: NSEvent.ModifierFlags) -> EventModifiers {
    let flags = flags.intersection(.deviceIndependentFlagsMask)
    var modifiers: EventModifiers = []
    if flags.contains(.command) { modifiers.insert(.command) }
    if flags.contains(.shift) { modifiers.insert(.shift) }
    if flags.contains(.option) { modifiers.insert(.option) }
    if flags.contains(.control) { modifiers.insert(.control) }
    return modifiers
  }
}
