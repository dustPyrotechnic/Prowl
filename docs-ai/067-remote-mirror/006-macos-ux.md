# 067.006 — macOS Remote Mirror UX

## Status

Implemented; native visual acceptance pending, 2026-09-13. Implementation branch: `fix/remote-mirror-ux`.

## Findings

- `MirrorHostButton.swift` fixes the popover height at 300–760 points, independent
  of content. Its comment records an AppKit animated-layout reentry risk.
- The toolbar uses primary/green for stopped/running, without subscriber state.
- `ToolbarPopoverCoordinator.swift` already supports the mirror destination but
  the button does not forward hover events.
- `MirrorSavedConnection.swift` stores credentials per endpoint and a last-used
  endpoint. The connection UI exposes only the last-used form, not a Host list.
- `MirrorHost.swift` owns authenticated device/peer and pane subscription maps;
  these can provide activity without a wire-protocol change.
- `MirrorTerminalViewport.swift` deliberately starts at the bottom of an
  unflipped AppKit document. Short output can therefore sit above the viewport.

## Implemented behavior

Use the existing shared toolbar coordinator, native controls, semantic system
colors, and section typography. The Remote Mirror popover contains Host above
Client, replacing the entry in Add to Prowl. Gray means stopped, muted blue means
listening without subscriptions, and muted green means at least one mirror.
Include a textual status and accessible label for the same distinction.

Size the panel to its content with a bounded scrolling region. Avoid animated
size transitions. Pairing uses a modal sheet with code, expiry, Copy, Refresh,
Cancel, and directions to Remote Mirror > Client > Connect to Host on the other
Mac. Cancel invalidates the unused code; it does not revoke completed pairing.

List saved credential-backed endpoints and connect on selection, opening the pane
picker after authentication. Do not start network connections on toolbar hover
or claim a saved Host is online before connecting. Preserve existing Keychain
records and expose Keychain failures. Host device rows show mirror count and
pane labels; disconnected devices remain visible.

## Viewport decision

Keep Host grid dimensions authoritative by default. Resizing the Host would
reflow its application and affect local users, so it requires an explicit future
control contract. Options for Client presentation:

| Option | Benefit | Cost |
| --- | --- | --- |
| Fit whole terminal (recommended default) | No initial two-axis scrolling; all context visible | Small text for very large Host grids |
| Original size, top anchored | Readable glyphs; short initial output visible | Two-axis navigation for smaller Client windows |
| Resize Host | Native Client text size and layout | Disrupts local Host/TUI state and needs ownership rules |

Accepted by the user: default to Fit to Window, with an Original Size option.
Use AppKit scroll-view magnification; retain the exact Host grid and input route.
Use a top-origin document for initial placement and preserve manual offsets in
Original Size. Shrink to fit; do not enlarge smaller terminals.
Do not infer cursor-follow behavior from screen height. A later cursor-follow
mode requires reliable cursor location and rules for manual scroll overrides.

Apple references: [NSScrollView magnification](https://developer.apple.com/documentation/appkit/nsscrollview/allowsmagnification)
and [NSView coordinate origin](https://developer.apple.com/documentation/appkit/nsview/isflipped).
The existing `GhosttySurfaceView.swift` mirror-grid path ignores viewport dimensions
when setting terminal rows and columns; this is the code basis for local-only scaling.

## Verification

- Focused tests: saved endpoint enumeration/deduplication, pairing cancellation,
  per-device subscription counts and cleanup, toolbar coordinator regressions.
- Viewport tests after the default is selected: smaller/larger clients, first
  layout, resize, bounds clamping, and explicit scroll preservation.
- Run `make check`, `make build-app`, and focused App-hosted tests.
- Debug visual pass: toolbar states/hover transfer, compact stopped/running
  panel, pairing cancellation/refresh, saved-host success/failure, pane picker,
  normal/constrained windows, and terminal input after viewport changes.

## Outcome

The unified toolbar surface, paired-Host entry list, cancellable pairing sheet,
per-device pane activity, and Fit to Window / Original Size viewport are implemented.
No transport protocol, Host PTY sizing, credential format, or dependency changed.
Existing endpoint records are enumerated from Keychain and deduplicated for display.

The content-height measurement belongs to the popover content, separate from its
toolbar owner. The sheet uses a separate presentation anchor. Panel resize animation
is disabled. User interaction pins the hover panel before Host mutations; opening a
modal dismisses the preview. Viewing saved entries does not connect to Hosts.

Validation before publication:

- `make check`: passed, including 158 script tests.
- Focused App-hosted tests: 18 passed after final cleanup, including real Ghostty
  viewport, input, history, takeover, pairing, and toolbar coordination. Viewport
  coverage includes fitting smaller windows, restoring original size, preserving
  manual scroll offsets on resize, and not enlarging terminals in larger windows.
- Final `make build-app`: passed with zero errors and warnings.

Native acceptance limitation: Computer Use can inspect the isolated Debug main
window but does not expose the toolbar popover in its accessibility tree or window
screenshot. Temporary instrumentation confirmed the presentation state and popover
appearance callback. The same tool limitation reproduced with the unchanged existing
Debug app. It is not evidence that either popover is invisible to the user. Temporary
diagnostics were removed. No native visual pass is claimed for the popover, sheet,
status colors, saved-Host flow, or scaled Metal rendering. These remain review gates;
the automated terminal snapshot tests do not replace visual rendering acceptance.

The acceptance app used `/tmp/prowl-mirror-ux-data` and a separate temporary bundle
identifier; existing Debug sessions and their active mirror were not restarted.

## Remaining product questions

None for this slice. Cursor-follow, Client-driven Host resizing, changed-address
recovery, and network discovery require separate decisions if requested later.

## Saved-Host Keychain correction

A user screenshot exposed OSStatus -50 when opening the Client section. The list
query combined `kSecMatchLimitAll` with `kSecReturnData` for password items, which
macOS does not support. The earlier tests covered deduplication but did not execute
that query. The correction enumerates attributes first, then reads each account
with `kSecMatchLimitOne`. Its regression test uses real temporary Keychain records
under a unique service, never personal pairing records.

Saved-Host discovery is optional. Its failure must not present a red OSStatus code
or block manual connection. Show a neutral recovery hint and keep Connect to Host
available. Credential operations that prevent connection or persistence still
report failure in plain language; diagnostic status codes belong in SupaLogger.

Correction verification: the real-Keychain regression first failed with
`KeychainError(status: -50)`, then passed after the query change. All 16 selected
credential and real-terminal tests passed, including damaged-entry and empty-list
cases. `make check` passed with 158 script tests; `make build-app` passed with zero
errors and warnings. The correction is included in PR #802.

## Review follow-up

Accept review items 1, 4, and 5: load saved credentials only after an explicit
click, cache the result in memory, update that cache after enrollment, keep errors
free of logging side effects, and enumerate only endpoint accounts accepted by the
reconnect path. An explicit retry remains available if discovery failed. The real
login-Keychain test becomes opt-in; deterministic query tests remain in the default
suite. Add a comment for subscription-count publication and let the pairing sheet
wait for listener readiness before its first code request.

Do not change the viewport decision: Fit to Window is the accepted default and
shows the whole grid. Original Size remains top-origin to address the reported
short-output blank viewport. A cursor-follow policy needs separate evidence and
rules. The user will verify item 2 (native popover resize behavior); no new native
acceptance claim is made here.

Review verification: 18 default credential/terminal regressions passed. The
opt-in real-Keychain test also passed when run separately with
`TEST_RUNNER_PROWL_RUN_KEYCHAIN_TESTS=1` and
`-only-testing:supacodeTests/MirrorDevicePairingTests/savedHostsRoundTripThroughKeychain()`.
Default query tests enforce attribute-only enumeration, one-at-a-time data reads,
and exclusion of `last-verified-host`. Cache tests cover lazy reads, enrollment
updates, and retry after an explicit lookup failure. `make check` passed with
158 script tests. Native popover sizing acceptance remains with the user.
The final Debug build passed with zero errors and warnings.
