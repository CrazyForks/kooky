import AppKit

/// Menu-bar-specific Kooky mark. Keep the Dock icon's tile-and-glyph identity,
/// but flatten it to a crisp white tile with a black `>_` at menu-bar size.
@MainActor
enum KookyMenuBarIcon {
    static let size = NSSize(width: 18, height: 18)

    static func make() -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.white.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 1, y: 1, width: 16, height: 16),
                xRadius: 4,
                yRadius: 4
            ).fill()

            NSColor.black.setStroke()

            let chevron = NSBezierPath()
            chevron.move(to: NSPoint(x: 4, y: 14))
            chevron.line(to: NSPoint(x: 9.25, y: 9.5))
            chevron.line(to: NSPoint(x: 4, y: 5))
            chevron.lineWidth = 1.8
            chevron.lineCapStyle = .butt
            chevron.lineJoinStyle = .miter
            chevron.stroke()

            let underscore = NSBezierPath()
            underscore.move(to: NSPoint(x: 9.25, y: 5))
            underscore.line(to: NSPoint(x: 15, y: 5))
            underscore.lineWidth = 1.8
            underscore.lineCapStyle = .butt
            underscore.stroke()
            return true
        }
        // A template image would tint the tile and glyph as one colour. This
        // mark intentionally keeps its white background and black foreground.
        image.isTemplate = false
        return image
    }
}
