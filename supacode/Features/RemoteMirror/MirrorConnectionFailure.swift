import Foundation
import Network
import Security

/// User-facing classification of a transport failure. Raw Network.framework text belongs in the log.
nonisolated enum MirrorConnectionFailure: Equatable, Sendable {
  case handshakeRejected(OSStatus)
  case refused
  case unreachable
  case unresolvable
  case timedOut
  case addressInUse
  case addressUnavailable
  case other(String)

  init(_ error: NWError) {
    switch error {
    case .tls(let status):
      self = .handshakeRejected(status)
    case .posix(let code):
      switch code {
      case .ECONNREFUSED: self = .refused
      case .EHOSTUNREACH, .ENETUNREACH, .EHOSTDOWN, .ENETDOWN: self = .unreachable
      case .ETIMEDOUT: self = .timedOut
      case .EADDRINUSE: self = .addressInUse
      case .EADDRNOTAVAIL: self = .addressUnavailable
      default: self = .other(error.localizedDescription)
      }
    case .dns:
      self = .unresolvable
    default:
      self = .other(error.localizedDescription)
    }
  }

  /// Message for an outgoing connection. `pairing` is true while a temporary code is presented.
  func clientMessage(endpoint: String, pairing: Bool) -> String {
    switch self {
    case .handshakeRejected:
      pairing
        ? "Host rejected the pairing code. Check the code, or refresh it on Host and try again."
        : "This Host no longer recognizes this Mac. Enter a new pairing code from Host."
    case .refused:
      "Nothing is listening at \(endpoint). Check that Host is started and the port is correct."
    case .unreachable:
      "Cannot reach \(endpoint). Check that both Macs are on the same network or VPN."
    case .unresolvable:
      "Cannot resolve the address \(endpoint). Check the name or use an IP address."
    case .timedOut:
      "No response from \(endpoint). Check the address and that Host is started."
    case .addressInUse, .addressUnavailable, .other:
      "Cannot connect to \(endpoint): \(detail)"
    }
  }

  /// Message for a listener that failed to start or stopped.
  func listenerMessage(address: String, port: String) -> String {
    switch self {
    case .addressInUse:
      "Port \(port) is already in use. Stop the other program or choose another port."
    case .addressUnavailable:
      "This Mac has no network interface with the address \(address)."
    default:
      "Cannot start Host: \(detail)"
    }
  }

  private var detail: String {
    switch self {
    case .handshakeRejected(let status): "TLS handshake failed (\(status))."
    case .refused: "connection refused."
    case .unreachable: "network unreachable."
    case .unresolvable: "address not resolved."
    case .timedOut: "timed out."
    case .addressInUse: "address already in use."
    case .addressUnavailable: "address not available."
    case .other(let text): text
    }
  }
}
