import AppKit

/// Menu-bar-specific Kooky mark. The full AppIcon's rounded tile, colour, and
/// shading are correct in the Dock but turn into a tiny sticker at 18pt.
/// Drawing just the `>_` brand mark as a template image lets AppKit tint it
/// white/black with the menu bar while keeping the geometry sharp on Retina.
@MainActor
enum KookyMenuBarIcon {
    static let size = NSSize(width: 18, height: 18)

    static func make() -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
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
        image.isTemplate = true
        return image
    }
}
