# 067.007 — macOS Remote Mirror UX polish

## Status

Implemented 2026-09-13 on `feat/remote-mirror-ux-polish`; native visual acceptance by the user pending.

## Findings

A review of the toolbar popover, the pairing sheet and the connection sheet against
[006](006-macos-ux.md) found these defects:

- `MirrorConnection` ignored `.waiting` before the transport became ready. A probe
  showed a revoked device key reports `.waiting(-9864: unknown PSK identity)` and a
  closed port reports `.waiting(Connection refused)` within 10 ms. The connection
  sheet stayed at Connecting… for the 30-second handshake deadline and then showed
  a generic timeout.
- The pairing code field was a `SecureField`; the user could not see the code.
- Saved Hosts were enumerated from Keychain, so hover previews needed an explicit
  Load Saved Hosts step and the list had no name, no delete and no rename.
- The pairing sheet did not report success, did not close, and did not tell the
  user which address to enter. Free-text Listen IP accepted addresses this Mac does
  not have and reported the raw POSIX error.
- The client rejected host names, so `mini.local` and VPN names could not be used.

## Decisions

- No wire-protocol change. A Host-side approval step for incoming pairing was
  considered and deferred: it needs a pending state on both ends and a
  synchronized iOS client. The code already proves screen access to Host.
- Non-secret Host metadata (address, port, alias, hostID, pairing and connection
  times) moves to `UserDefaults` in `MirrorKnownHostStore`. Keychain keeps only the
  device credential and is read at connect time, once for a legacy import after an
  explicit click, and on Forget. Hover never reads Keychain.
- Host names are displayed as a local alias. Reverse DNS was rejected as slow and
  unreliable on LANs.
- Pre-ready `.waiting` is a failure. `MirrorConnectionFailure` classifies the
  `NWError` and composes user text with the endpoint and pairing context. The
  client handshake deadline is ten seconds.
- The connection form shows the code field only when no saved access exists for the
  endpoint, or after a TLS rejection of a saved credential.
- Listen address is a picker over this Mac's interfaces. The pairing sheet lists the
  Bonjour name and each reachable interface with the port, and explains reachability.

## Verification

- Focused App-hosted tests: 35 passed, including pairing success recording, TLS
  rejection reported at once with the plain-language reason, refused connection
  ending before the deadline, store import/rename/forget/persistence, failure
  mapping, reachable-address selection, endpoint validation and code formatting.
- `make check` passed with 158 script tests. `make build-app` passed.
- Not verified: native appearance of the picker, confirmation dialog and rename
  alert inside the popover, and the pairing sheet auto-dismiss timing.
