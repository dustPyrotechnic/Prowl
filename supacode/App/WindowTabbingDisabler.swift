import AppKit
import SwiftUI

struct WindowTabbingDisabler: NSViewRepresentable {
  /// Ghostty's `undo` / `redo` triggers, caught by the main window when no
  /// terminal surface can take them (docs-ai 069).
  var undoShortcuts: TerminalCloseUndoKeyMonitor.Shortcuts
  var undoClose: @MainActor () -> Bool
  var redoClose: @MainActor () -> Bool

  func makeNSView(context: Context) -> WindowTabbingView {
    WindowTabbingView()
  }

  func updateNSView(_ nsView: WindowTabbingView, context: Context) {
    nsView.installUndoKeyMonitor(shortcuts: undoShortcuts, undo: undoClose, redo: redoClose)
    nsView.disallowTabbing()
  }
}

final class WindowTabbingView: NSView, NSWindowDelegate {
  private var undoKeyMonitor: TerminalCloseUndoKeyMonitor?
  private var undoShortcuts: TerminalCloseUndoKeyMonitor.Shortcuts?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    disallowTabbing()
  }

  func disallowTabbing() {
    guard let window else { return }
    window.tabbingMode = .disallowed
    window.identifier = NSUserInterfaceItemIdentifier(WindowID.main)
    // Persist the main window's position and size across launches. Idempotent:
    // re-associating the same autosave name on later passes is a no-op.
    window.setFrameAutosaveName(NSWindow.FrameAutosaveName(WindowID.main))
    window.isExcludedFromWindowsMenu = true
    if window.delegate !== self {
      window.delegate = self
    }
  }

  /// One monitor per set of triggers; SwiftUI re-runs `updateNSView` often and
  /// the closures it hands over are equivalent every time.
  func installUndoKeyMonitor(
    shortcuts: TerminalCloseUndoKeyMonitor.Shortcuts,
    undo: @escaping @MainActor () -> Bool,
    redo: @escaping @MainActor () -> Bool
  ) {
    guard undoShortcuts != shortcuts else { return }
    undoShortcuts = shortcuts
    undoKeyMonitor = TerminalCloseUndoKeyMonitor(shortcuts: shortcuts, undo: undo, redo: redo)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if Self.shouldOrderOutOnClose(styleMask: sender.styleMask) {
      sender.orderOut(nil)
    }
    return false
  }

  static func shouldOrderOutOnClose(styleMask: NSWindow.StyleMask) -> Bool {
    !styleMask.contains(.fullScreen)
  }
}
