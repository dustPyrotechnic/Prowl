import Foundation
import ProwlCLIShared

/// Undo for pane and tab closes (docs-ai 069).
///
/// A close detaches its surfaces instead of freeing them: every observer sees
/// the close as before (`forgetSurface` still runs), but the
/// `GhosttySurfaceView`s stay alive inside a `TerminalCloseRecord` until the
/// owner restores or frees them. Restore re-runs the adoption steps of tab
/// creation, so a restored pane is a new pane to the CLI (fresh handle) and
/// to agent detection, while its process, scrollback, and split position are
/// the original ones.
extension WorktreeTerminalState {
  /// Captures what `closeTab` is about to destroy. `nil` when undo is off or
  /// the tab has no tree to keep.
  func makeClosedTabRecord(for tabId: TerminalTabID) -> TerminalClosedTabRecord? {
    guard undoCloseTimeout > .zero,
      let index = tabManager.tabs.firstIndex(where: { $0.id == tabId }),
      let tree = trees[tabId]
    else { return nil }
    return TerminalClosedTabRecord(
      item: tabManager.tabs[index],
      index: index,
      wasSelected: tabManager.selectedTabId == tabId,
      tree: tree,
      focusedSurfaceID: focusedSurfaceIdByTab[tabId],
      wasRunScriptTab: tabId == runScriptTabId,
      boundDirectoryKey: boundDirectoryTabIDs.first { $0.value == tabId }?.key
    )
  }

  /// `removeTree(for:)` with the leaves detached instead of freed.
  func detachTree(for tabId: TerminalTabID) {
    guard let tree = trees.removeValue(forKey: tabId) else { return }
    for surface in tree.leaves() {
      detachSurface(surface)
      forgetSurface(surface.id)
    }
    focusedSurfaceIdByTab.removeValue(forKey: tabId)
    tabIsRunningById.removeValue(forKey: tabId)
    tabAgentBusyById.removeValue(forKey: tabId)
    tabAgentBlockedById.removeValue(forKey: tabId)
  }

  /// Suspends the view and disconnects it from this state. Only a process
  /// exit still reaches us, so the record can drop a surface that died.
  func detachSurface(_ view: GhosttySurfaceView) {
    view.suspendForPendingClose()
    let bridge = view.bridge
    bridge.onUndo = nil
    bridge.onRedo = nil
    bridge.onTitleChange = nil
    bridge.onSplitAction = nil
    bridge.onNewTab = nil
    bridge.onCloseTab = nil
    bridge.onGotoTab = nil
    bridge.onCommandPaletteToggle = nil
    bridge.onProgressReport = nil
    bridge.onDesktopNotification = nil
    bridge.onCommandFinished = nil
    bridge.onPromptTitle = nil
    bridge.onCloseRequest = { [weak self, weak view] _ in
      guard let self, let view else { return }
      onRetainedSurfaceExited?(view.id)
    }
    view.onFocusChange = nil
    view.onKeyInput = nil
    view.onFontSizeShortcut = nil
  }

  func recordClosedTab(_ record: TerminalClosedTabRecord) {
    if pendingCloseGroup != nil {
      pendingCloseGroup?.append(record)
    } else {
      onCloseRecorded?(.tabs(worktreeID: worktreeID, [record]))
    }
  }

  /// Puts a closed tab back at its index with its tree. Returns `false` when
  /// the tab is somehow present again; the caller then frees the record.
  @discardableResult
  func restore(tab record: TerminalClosedTabRecord) -> Bool {
    let tabId = record.tabID
    guard !tabManager.tabs.contains(where: { $0.id == tabId }) else { return false }
    tabManager.insertTab(record.item, at: record.index, select: record.wasSelected)
    trees[tabId] = record.tree
    for leaf in record.tree.leaves() {
      adoptRetainedSurface(leaf, tabId: tabId)
    }
    _ = registerTargetHandle(for: tabId)
    tabIsRunningById[tabId] = false
    if let key = record.boundDirectoryKey {
      boundDirectoryTabIDs[key] = tabId
    }
    if record.wasRunScriptTab {
      setRunScriptTabId(tabId)
    }
    let focusTarget =
      record.focusedSurfaceID.flatMap { surfaces[$0] } ?? record.tree.root?.leftmostLeaf()
    if let focusTarget {
      focusedSurfaceIdByTab[tabId] = focusTarget.id
    }
    updateRunningState(for: tabId)
    updateTabAgentBusyState(for: tabId)
    if tabManager.selectedTabId == tabId, let focusTarget {
      focusSurface(focusTarget, in: tabId)
    }
    syncFocusIfNeeded()
    emitTaskStatusIfChanged()
    onTabCreated?()
    return true
  }

  /// Puts a closed pane back by reinstating the tab's pre-close tree. Returns
  /// `false` when the tab changed structurally since the close (another split,
  /// a moved pane); the caller then frees the record.
  @discardableResult
  func restore(pane record: TerminalClosedPaneRecord) -> Bool {
    let tabId = record.tabID
    guard tabManager.tabs.contains(where: { $0.id == tabId }), let current = trees[tabId] else {
      return false
    }
    let expected = Set(record.previousTree.leaves().map(\.id)).subtracting([record.view.id])
    guard Set(current.leaves().map(\.id)) == expected else { return false }
    adoptRetainedSurface(record.view, tabId: tabId)
    updateTree(record.previousTree, for: tabId)
    updateRunningState(for: tabId)
    updateTabAgentBusyState(for: tabId)
    if record.wasFocused {
      focusSurface(record.view, in: tabId)
    }
    return true
  }

  /// The surface-level half of `createTab`'s adoption for a retained view.
  private func adoptRetainedSurface(_ view: GhosttySurfaceView, tabId: TerminalTabID) {
    view.resumeFromPendingClose()
    configureBridgeCallbacks(for: view, tabId: tabId)
    configureSurfaceCallbacks(for: view, tabId: tabId)
    surfaces[view.id] = view
    _ = registerTargetHandle(for: view.id)
    wakeAgentDetection(for: view, tabId: tabId)
  }
}
