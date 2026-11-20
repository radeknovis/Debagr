import AppKit

/// Template artwork keeps status legible in light, dark, and highlighted menu bars.
enum MenuBarIconState: CaseIterable {
  case idle, checking, ready, paused, attention

  var image: NSImage {
    let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
      NSColor.black.setStroke()
      NSColor.black.setFill()
      let phone = NSBezierPath(
        roundedRect: NSRect(x: 2, y: 1, width: 10, height: 16),
        xRadius: 2, yRadius: 2)
      phone.lineWidth = 1.5
      phone.stroke()
      let speaker = NSBezierPath()
      speaker.move(to: NSPoint(x: 5, y: 14.5))
      speaker.line(to: NSPoint(x: 9, y: 14.5))
      speaker.lineWidth = 1.2
      speaker.stroke()
      NSBezierPath(ovalIn: NSRect(x: 6, y: 3, width: 2, height: 1.2)).fill()

      // Knock out the phone edge so the badge remains readable at native size.
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current?.compositingOperation = .clear
      NSBezierPath(ovalIn: NSRect(x: 9, y: 0, width: 13, height: 13)).fill()
      NSGraphicsContext.restoreGraphicsState()
      NSColor.black.setStroke()
      NSColor.black.setFill()
      let badge = NSBezierPath(ovalIn: NSRect(x: 10.5, y: 1.5, width: 10, height: 10))
      badge.lineWidth = 1.3
      badge.stroke()
      let mark = NSBezierPath()
      mark.lineWidth = 1.4
      mark.lineCapStyle = .round
      mark.lineJoinStyle = .round
      switch self {
      case .ready:
        mark.move(to: NSPoint(x: 12.5, y: 6.5))
        mark.line(to: NSPoint(x: 14.5, y: 4.5))
        mark.line(to: NSPoint(x: 18.5, y: 8.5))
      case .attention:
        mark.move(to: NSPoint(x: 15.5, y: 9))
        mark.line(to: NSPoint(x: 15.5, y: 6.5))
        NSBezierPath(ovalIn: NSRect(x: 14.8, y: 3.5, width: 1.4, height: 1.4)).fill()
      case .paused:
        for x in [14.0, 17.0] {
          mark.move(to: NSPoint(x: x, y: 4))
          mark.line(to: NSPoint(x: x, y: 9))
        }
      case .checking:
        mark.move(to: NSPoint(x: 15.5, y: 9))
        mark.line(to: NSPoint(x: 15.5, y: 6.5))
        mark.line(to: NSPoint(x: 18, y: 6.5))
      case .idle:
        mark.move(to: NSPoint(x: 13, y: 6.5))
        mark.line(to: NSPoint(x: 18, y: 6.5))

      }
      mark.stroke()
      return true
    }
    image.isTemplate = true
    return image
  }
}
