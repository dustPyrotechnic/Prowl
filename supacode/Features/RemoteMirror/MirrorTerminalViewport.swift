import AppKit
import SwiftUI

struct MirrorTerminalViewport: NSViewRepresentable {
  let surface: GhosttySurfaceView
  let displaySize: CGSize
  var fitsWindow = true

  func makeNSView(context: Context) -> MirrorTerminalScrollView {
    MirrorTerminalScrollView(surface: surface, displaySize: displaySize, fitsWindow: fitsWindow)
  }

  func updateNSView(_ view: MirrorTerminalScrollView, context: Context) {
    view.update(surface: surface, displaySize: displaySize, fitsWindow: fitsWindow)
  }
}

final class MirrorTerminalScrollView: NSScrollView {
  private final class Document: NSView {
    override var isFlipped: Bool { true }
  }

  private var surface: GhosttySurfaceView
  private let document = Document()
  private var fitsWindow: Bool
  private var resetOrigin = true
  private var isLayingOut = false
  var displaySize: CGSize {
    didSet { if displaySize != oldValue { needsLayout = true } }
  }

  init(surface: GhosttySurfaceView, displaySize: CGSize, fitsWindow: Bool = true) {
    self.surface = surface
    self.displaySize = displaySize
    self.fitsWindow = fitsWindow
    super.init(frame: .zero)
    hasHorizontalScroller = true
    hasVerticalScroller = true
    autohidesScrollers = true
    scrollerStyle = .overlay
    drawsBackground = false
    minMagnification = 0.01
    maxMagnification = 1
    // A top-origin document also keeps short terminals at the top of larger windows.
    // The surface retains its Host grid; magnification changes only presentation.
    documentView = document
    document.addSubview(surface)
  }

  func update(surface: GhosttySurfaceView, displaySize: CGSize, fitsWindow: Bool = true) {
    if self.surface !== surface {
      self.surface.removeFromSuperview()
      self.surface = surface
      document.addSubview(surface)
      resetOrigin = true
      needsLayout = true
    }
    if self.fitsWindow != fitsWindow {
      self.fitsWindow = fitsWindow
      resetOrigin = true
      needsLayout = true
    }
    self.displaySize = displaySize
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func layout() {
    guard !isLayingOut else { return }
    isLayingOut = true
    defer { isLayingOut = false }
    let origin = resetOrigin || fitsWindow ? NSPoint.zero : contentView.bounds.origin
    super.layout()
    document.setFrameSize(displaySize)
    surface.setFrameSize(displaySize)
    surface.updateSurfaceSize()
    let scale =
      fitsWindow
      ? min(1, contentSize.width / max(1, displaySize.width), contentSize.height / max(1, displaySize.height))
      : 1
    let target = max(minMagnification, scale)
    if abs(magnification - target) > 0.0001 { magnification = target }
    let visible = contentView.bounds.size
    contentView.scroll(
      to: NSPoint(
        x: min(max(0, origin.x), max(0, displaySize.width - visible.width)),
        y: min(max(0, origin.y), max(0, displaySize.height - visible.height))
      ))
    reflectScrolledClipView(contentView)
    resetOrigin = false
  }
}
