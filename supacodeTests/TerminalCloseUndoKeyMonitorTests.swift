import AppKit
import SwiftUI
import Testing

@testable import supacode

/// Routing for ⌘Z / ⌘⇧Z when no terminal surface has focus (docs-ai 069).
@MainActor
struct TerminalCloseUndoKeyMonitorTests {
  private let defaults = TerminalCloseUndoKeyMonitor.Shortcuts.ghosttyDefaults

  @Test func undoAndRedoKeysRouteToTheCloseStack() {
    #expect(route("z", [.command]) == .undo)
    #expect(route("z", [.command, .shift]) == .redo)
    #expect(route("Z", [.command, .shift]) == .redo)
  }

  /// Ghostty binds both `super+z` and `super+shift+t` to `undo` by default.
  @Test func defaultShiftTAliasRoutesToUndo() {
    #expect(route("t", [.command, .shift]) == .undo)
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

  /// Ghostty's reverse lookup hides the (performable) defaults and keeps one
  /// trigger per action, so a resolved trigger adds to the defaults.
  @Test func resolvedTriggersAreAdditiveToTheDefaults() {
    let shortcuts = TerminalCloseUndoKeyMonitor.Shortcuts.resolving(
      undo: KeyboardShortcut("u", modifiers: .command),
      redo: KeyboardShortcut("y", modifiers: .command)
    )
    #expect(route("u", [.command], shortcuts: shortcuts) == .undo)
    #expect(route("z", [.command], shortcuts: shortcuts) == .undo)
    #expect(route("t", [.command, .shift], shortcuts: shortcuts) == .undo)
    #expect(route("y", [.command], shortcuts: shortcuts) == .redo)
    #expect(route("z", [.command, .shift], shortcuts: shortcuts) == .redo)
  }

  @Test func resolvingNothingKeepsTheDefaultsWithoutDuplicates() {
    let defaults = TerminalCloseUndoKeyMonitor.Shortcuts.ghosttyDefaults
    #expect(TerminalCloseUndoKeyMonitor.Shortcuts.resolving(undo: nil, redo: nil) == defaults)
    let resolved = TerminalCloseUndoKeyMonitor.Shortcuts.resolving(
      undo: KeyboardShortcut("z", modifiers: .command),
      redo: KeyboardShortcut("z", modifiers: [.command, .shift])
    )
    #expect(resolved == defaults)
  }

  @Test func eventsFromAnotherWindowPassThrough() {
    let owner = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
    let other = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
    let event = keyEvent("z", [.command], windowNumber: other.windowNumber)
    #expect(event.window === other)

    #expect(TerminalCloseUndoKeyMonitor.decision(for: event, ownerWindow: owner, shortcuts: defaults) == .pass)
    #expect(TerminalCloseUndoKeyMonitor.decision(for: event, ownerWindow: nil, shortcuts: defaults) == .pass)
    #expect(TerminalCloseUndoKeyMonitor.decision(for: event, ownerWindow: other, shortcuts: defaults) == .undo)
  }

  @Test func eventsForTheOwnerWindowRespectItsFirstResponder() {
    let owner = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
    let redo = keyEvent("z", [.command, .shift], windowNumber: owner.windowNumber)
    #expect(TerminalCloseUndoKeyMonitor.decision(for: redo, ownerWindow: owner, shortcuts: defaults) == .redo)

    let field = NSTextView(frame: .zero)
    owner.contentView?.addSubview(field)
    owner.makeFirstResponder(field)
    #expect(owner.firstResponder === field)
    #expect(TerminalCloseUndoKeyMonitor.decision(for: redo, ownerWindow: owner, shortcuts: defaults) == .pass)
  }

  private func keyEvent(_ characters: String, _ flags: NSEvent.ModifierFlags, windowNumber: Int) -> NSEvent {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: flags,
      timestamp: 0,
      windowNumber: windowNumber,
      context: nil,
      characters: characters,
      charactersIgnoringModifiers: characters,
      isARepeat: false,
      keyCode: 6
    )!
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
