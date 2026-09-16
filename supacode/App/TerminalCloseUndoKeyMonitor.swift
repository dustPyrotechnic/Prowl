import AppKit
import SwiftUI

/// Routes Ghostty's `undo` / `redo` keys to the close-undo stack when no
/// terminal surface can take them (docs-ai 069).
///
/// A focused terminal handles the keys itself through Ghostty's binding. After
/// the last tab of a worktree closes, the terminal area is empty and nothing
/// receives ⌘Z: SwiftUI's Edit › Undo does not consult the window's undo
/// manager, so a local key monitor is the one place the key can be caught.
/// Text editing keeps its own undo: a field editor as first responder passes
/// the key through untouched.
@MainActor
final class TerminalCloseUndoKeyMonitor {
  enum Route: Equatable {
    case undo
    case redo
    case pass
  }

  /// The resolved triggers, normally Ghostty's `undo` / `redo` bindings.
  struct Shortcuts: Equatable {
    var undo: KeyboardShortcut
    var redo: KeyboardShortcut

    static let ghosttyDefaults = Shortcuts(
      undo: KeyboardShortcut("z", modifiers: .command),
      redo: KeyboardShortcut("z", modifiers: [.command, .shift])
    )
  }

  private var monitor: Any?

  init(
    shortcuts: Shortcuts,
    undo: @escaping @MainActor () -> Bool,
    redo: @escaping @MainActor () -> Bool
  ) {
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let handled = MainActor.assumeIsolated { () -> Bool in
        guard let window = event.window, window.isKeyWindow else { return false }
        let route = Self.route(
          characters: event.charactersIgnoringModifiers,
          modifierFlags: event.modifierFlags,
          firstResponderOwnsUndo: Self.firstResponderOwnsUndo(window.firstResponder),
          shortcuts: shortcuts
        )
        switch route {
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
    if matches(shortcuts.redo, characters: characters, modifiers: modifiers) { return .redo }
    if matches(shortcuts.undo, characters: characters, modifiers: modifiers) { return .undo }
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
