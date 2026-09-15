import ComposableArchitecture
import Foundation

extension AppFeature {
  /// Open the hand-off HUD for the active runnable target: the selected
  /// worktree in Normal/Shelf, or the focused card in Canvas. Requires a
  /// detected agent on the target pane — the no-source mechanical handoff
  /// stays CLI-only (docs-ai 049/058).
  func openHandoffHud(state: inout State) -> Effect<Action> {
    guard state.handoffHud == nil else { return .none }
    guard let worktree = actionTargetWorktree(repositories: state.repositories) else { return .none }
    let source = terminalClient.handoffSourceContext(worktree.id)
    guard let hudState = HandoffHudFeature.State.make(worktree: worktree, source: source) else {
      return .send(
        .repositories(.showToast(.warning(String(localized: "No agent detected in the current pane"))))
      )
    }
    state.handoffHud = hudState
    return .none
  }

  /// Open the hand-off HUD for a specific Active Agents entry (context menu).
  /// The source is captured from the entry's own pane, so it works regardless
  /// of which pane currently holds focus; RepositoriesFeature selects and
  /// focuses the entry's worktree from the same action.
  func openHandoffHud(state: inout State, entryID: ActiveAgentEntry.ID) -> Effect<Action> {
    guard state.handoffHud == nil else { return .none }
    guard let entry = state.repositories.activeAgents.entries[id: entryID],
      let worktree = state.repositories.terminalWorktree(for: entry.worktreeID)
    else { return .none }
    let source = terminalClient.handoffSourceContextForSurface(entry.worktreeID, entry.surfaceID)
    guard let hudState = HandoffHudFeature.State.make(worktree: worktree, source: source) else {
      return .send(
        .repositories(.showToast(.warning(String(localized: "No agent detected in this pane"))))
      )
    }
    state.handoffHud = hudState
    return .none
  }
}
