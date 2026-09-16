import Clocks
import Foundation
import GhosttyKit
import ProwlCLIShared
import Testing

@testable import supacode

/// Undo for pane and tab closes (docs-ai 069): the manager-level flow from a
/// close through ⌘Z / ⌘⇧Z, expiry, and invalidation.
@MainActor
@Suite(.serialized)
struct WorktreeTerminalUndoCloseTests {
  @Test func closedTabComesBackAtItsIndexWithTheSameSurface() throws {
    let fixture = makeFixture()
    let state = fixture.state
    let first = try #require(state.createTab())
    let second = try #require(state.createTab())
    let third = try #require(state.createTab())
    state.selectTab(second)
    let surfaceID = try #require(state.focusedSurfaceId(in: second))
    let view = try #require(state.surfaceView(for: surfaceID))
    let handleBefore = state.paneHandle(for: surfaceID)

    #expect(state.closeTab(second))
    #expect(state.tabManager.tabs.map(\.id) == [first, third])
    #expect(state.surfaceView(for: surfaceID) == nil)
    #expect(view.isPendingClose)
    #expect(fixture.manager.closeUndoStack.canUndo)

    #expect(fixture.manager.undoClose())

    #expect(state.tabManager.tabs.map(\.id) == [first, second, third])
    #expect(state.tabManager.selectedTabId == second)
    #expect(state.surfaceView(for: surfaceID) === view)
    #expect(state.focusedSurfaceId(in: second) == surfaceID)
    #expect(!view.isPendingClose)
    #expect(state.paneHandle(for: surfaceID) != handleBefore)
    #expect(!fixture.manager.closeUndoStack.canUndo)
    #expect(fixture.manager.closeUndoStack.canRedo)
  }

  @Test func closedPaneComesBackInItsSplitPosition() throws {
    let fixture = makeFixture()
    let state = fixture.state
    let tab = try #require(state.createTab())
    let anchor = try #require(state.focusedSurfaceId(in: tab))
    let pane = try state.createSplit(of: anchor, direction: .right, initialInput: nil).get()
    let before = state.splitTree(for: tab)
    let view = try #require(state.surfaceView(for: pane))

    #expect(state.closeSurface(id: pane))
    #expect(state.splitTree(for: tab).leaves().map(\.id) == [anchor])
    #expect(state.focusedSurfaceId(in: tab) == anchor)

    #expect(fixture.manager.undoClose())

    let after = state.splitTree(for: tab)
    #expect(after.structuralIdentity == before.structuralIdentity)
    #expect(after.leaves().map(\.id) == [anchor, pane])
    #expect(state.surfaceView(for: pane) === view)
    #expect(state.focusedSurfaceId(in: tab) == pane)
  }

  @Test func undoWithNothingRecordedFallsThrough() {
    let fixture = makeFixture()
    #expect(!fixture.manager.undoClose())
    #expect(!fixture.manager.redoClose())
  }

  @Test func closeExpiresAfterTheGhosttyTimeout() async throws {
    let fixture = makeFixture()
    let state = fixture.state
    let tab = try #require(state.createTab())
    let surfaceID = try #require(state.focusedSurfaceId(in: tab))
    let view = try #require(state.surfaceView(for: surfaceID))

    #expect(state.closeTab(tab))
    #expect(view.isPendingClose)

    await fixture.clock.advance(by: .seconds(5))
    await settle()

    #expect(!fixture.manager.closeUndoStack.canUndo)
    #expect(!view.isPendingClose)
    #expect(!fixture.manager.undoClose())
    #expect(state.tabManager.tabs.isEmpty)
  }

  @Test func processExitDuringGraceDropsTheRecord() throws {
    let fixture = makeFixture()
    let state = fixture.state
    let tab = try #require(state.createTab())
    let surfaceID = try #require(state.focusedSurfaceId(in: tab))
    let view = try #require(state.surfaceView(for: surfaceID))

    #expect(state.closeTab(tab))
    view.bridge.closeSurface(processAlive: false)

    #expect(!fixture.manager.closeUndoStack.canUndo)
    #expect(!view.isPendingClose)
    #expect(!fixture.manager.undoClose())
  }

  @Test func deadProcessCloseIsNotRecorded() throws {
    let fixture = makeFixture()
    let state = fixture.state
    let tab = try #require(state.createTab())
    let surfaceID = try #require(state.focusedSurfaceId(in: tab))
    let view = try #require(state.surfaceView(for: surfaceID))

    #expect(state.handleCloseRequest(for: view, processAlive: false))

    #expect(!view.isPendingClose)
    #expect(!fixture.manager.closeUndoStack.canUndo)
  }

  @Test func zeroTimeoutKeepsFreeOnClose() throws {
    let fixture = makeFixture()
    let state = fixture.state
    state.undoCloseTimeout = .zero
    let tab = try #require(state.createTab())
    let surfaceID = try #require(state.focusedSurfaceId(in: tab))
    let view = try #require(state.surfaceView(for: surfaceID))

    #expect(state.closeTab(tab))

    #expect(!view.isPendingClose)
    #expect(!fixture.manager.closeUndoStack.canUndo)
  }

  @Test func batchCloseUndoesAsOneEntry() throws {
    let fixture = makeFixture()
    let state = fixture.state
    let first = try #require(state.createTab())
    let second = try #require(state.createTab())
    let third = try #require(state.createTab())
    state.selectTab(first)

    state.closeOtherTabs(keeping: first)
    #expect(state.tabManager.tabs.map(\.id) == [first])

    #expect(fixture.manager.undoClose())

    #expect(state.tabManager.tabs.map(\.id) == [first, second, third])
    #expect(state.tabManager.selectedTabId == first)
    #expect(!fixture.manager.closeUndoStack.canUndo)
  }

  @Test func redoClosesAgainAndStaysUndoable() throws {
    let fixture = makeFixture()
    let state = fixture.state
    let first = try #require(state.createTab())
    let second = try #require(state.createTab())

    #expect(state.closeTab(second))
    #expect(fixture.manager.undoClose())
    #expect(fixture.manager.redoClose())

    #expect(state.tabManager.tabs.map(\.id) == [first])
    #expect(fixture.manager.closeUndoStack.canUndo)
    #expect(!fixture.manager.closeUndoStack.canRedo)

    #expect(fixture.manager.undoClose())
    #expect(state.tabManager.tabs.map(\.id) == [first, second])
  }

  @Test func paneRecordIsDroppedWhenTheTabChangedShape() throws {
    let fixture = makeFixture()
    let state = fixture.state
    let tab = try #require(state.createTab())
    let anchor = try #require(state.focusedSurfaceId(in: tab))
    let pane = try state.createSplit(of: anchor, direction: .right, initialInput: nil).get()
    let view = try #require(state.surfaceView(for: pane))

    #expect(state.closeSurface(id: pane))
    _ = try state.createSplit(of: anchor, direction: .down, initialInput: nil).get()

    #expect(!fixture.manager.undoClose())
    #expect(!view.isPendingClose)
    #expect(state.splitTree(for: tab).leaves().count == 2)
    #expect(!fixture.manager.closeUndoStack.canUndo)
  }

  @Test func pruneFreesRetainedSurfacesOfRemovedWorktrees() throws {
    let fixture = makeFixture()
    let state = fixture.state
    let tab = try #require(state.createTab())
    let surfaceID = try #require(state.focusedSurfaceId(in: tab))
    let view = try #require(state.surfaceView(for: surfaceID))
    #expect(state.closeTab(tab))

    fixture.manager.prune(keeping: [])

    #expect(!view.isPendingClose)
    #expect(!fixture.manager.closeUndoStack.canUndo)
  }

  @Test func restoringTheLastTabReopensTheWorktreeAndRevealsIt() async throws {
    let fixture = makeFixture()
    let state = fixture.state
    let tab = try #require(state.createTab())
    let stream = fixture.manager.eventStream()
    #expect(state.closeTab(tab))
    fixture.manager.selectedWorktreeID = "/tmp/repo/other"

    #expect(fixture.manager.undoClose())

    var seen: [TerminalClient.Event] = []
    for await event in stream {
      seen.append(event)
      if case .tabRestored = event { break }
    }
    #expect(seen.contains(.tabCreated(worktreeID: fixture.worktree.id)))
    #expect(seen.last == .tabRestored(worktreeID: fixture.worktree.id))
  }

  @Test func undoIntoTheSelectedWorktreeDoesNotAskForReveal() async throws {
    let fixture = makeFixture()
    let state = fixture.state
    let tab = try #require(state.createTab())
    let stream = fixture.manager.eventStream()
    #expect(state.closeTab(tab))
    fixture.manager.selectedWorktreeID = fixture.worktree.id

    #expect(fixture.manager.undoClose())
    state.onSetupScriptConsumed?()

    var seen: [TerminalClient.Event] = []
    for await event in stream {
      seen.append(event)
      if case .setupScriptConsumed = event { break }
    }
    #expect(!seen.contains(.tabRestored(worktreeID: fixture.worktree.id)))
  }

  private struct Fixture {
    let manager: WorktreeTerminalManager
    let state: WorktreeTerminalState
    let worktree: Worktree
    let clock: TestClock<Duration>
  }

  private func makeFixture() -> Fixture {
    let clock = TestClock()
    let manager = WorktreeTerminalManager(
      runtime: GhosttyRuntime(),
      undoCloseClock: clock,
      skipsSurfaceCreationForTesting: true
    )
    let worktree = Worktree(
      id: "/tmp/repo/wt-1",
      name: "wt-1",
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt-1"),
      repositoryRootURL: URL(fileURLWithPath: "/tmp/repo")
    )
    return Fixture(manager: manager, state: manager.state(for: worktree), worktree: worktree, clock: clock)
  }

  private func settle() async {
    for _ in 0..<10 {
      await Task.yield()
    }
  }
}
