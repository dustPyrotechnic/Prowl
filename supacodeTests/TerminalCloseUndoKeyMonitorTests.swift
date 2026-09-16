import AppKit
import SwiftUI
import Testing

@testable import supacode

/// Routing for ⌘Z / ⌘⇧Z when no terminal surface has focus (docs-ai 069).
struct TerminalCloseUndoKeyMonitorTests {
  private let defaults = TerminalCloseUndoKeyMonitor.Shortcuts.ghosttyDefaults

  @Test func undoAndRedoKeysRouteToTheCloseStack() {
    #expect(route("z", [.command]) == .undo)
    #expect(route("z", [.command, .shift]) == .redo)
    #expect(route("Z", [.command, .shift]) == .redo)
  }

  @Test func otherKeysPassThrough() {
    #expect(route("z", []) == .pass)
    #expect(route("z", [.command, .option]) == .pass)
    #expect(route("x", [.command]) == .pass)
    #expect(route(nil, [.command]) == .pass)
  }

  @Test func aTerminalOrTextFieldKeepsItsOwnUndo() {
    #expect(route("z", [.command], ownsUndo: true) == .pass)
    #expect(route("z", [.command, .shift], ownsUndo: true) == .pass)
  }

  @Test func customGhosttyTriggersAreHonored() {
    let shortcuts = TerminalCloseUndoKeyMonitor.Shortcuts(
      undo: KeyboardShortcut("t", modifiers: [.command, .shift]),
      redo: KeyboardShortcut("y", modifiers: [.command])
    )
    #expect(route("t", [.command, .shift], shortcuts: shortcuts) == .undo)
    #expect(route("y", [.command], shortcuts: shortcuts) == .redo)
    #expect(route("z", [.command], shortcuts: shortcuts) == .pass)
  }

  @Test func firstResponderKindsThatOwnUndo() {
    #expect(TerminalCloseUndoKeyMonitor.firstResponderOwnsUndo(NSTextView()))
    #expect(!TerminalCloseUndoKeyMonitor.firstResponderOwnsUndo(NSView()))
    #expect(!TerminalCloseUndoKeyMonitor.firstResponderOwnsUndo(nil))
  }

  private func route(
    _ characters: String?,
    _ flags: NSEvent.ModifierFlags,
    ownsUndo: Bool = false,
    shortcuts: TerminalCloseUndoKeyMonitor.Shortcuts? = nil
  ) -> TerminalCloseUndoKeyMonitor.Route {
    TerminalCloseUndoKeyMonitor.route(
      characters: characters,
      modifierFlags: flags,
      firstResponderOwnsUndo: ownsUndo,
      shortcuts: shortcuts ?? defaults
    )
  }
}
