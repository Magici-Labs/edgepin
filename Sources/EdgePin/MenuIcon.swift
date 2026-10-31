import AppKit

/// The menu bar icon: a pin with a small sparkle at its top right, like the app
/// icon. Outlined, or filled while a pin is showing.
///
/// Drawn by hand rather than from system symbols so every straight edge lands
/// on a whole point, which keeps it sharp on 1x screens. Points are in a
/// 19x18 box with y going up.
enum MenuIcon {
    static func image(filled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 19, height: 18), flipped: false) { _ in
            draw(filled: filled)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "EdgePin"
        return image
    }

    private static func draw(filled: Bool) {
        NSColor.black.set()
        let body = pinBody()
        if filled {
            body.fill()
        } else {
            // A 1pt line just inside the edge: clip to the shape, stroke 2pt.
            NSGraphicsContext.saveGraphicsState()
            body.addClip()
            body.lineWidth = 2
            body.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
        NSRect(x: 6, y: 1, width: 1, height: 5).fill() // needle
        sparkle(center: NSPoint(x: 15.5, y: 14.5), radius: 3.5).fill()
    }

    /// Cap, neck and the rounded base, without the needle.
    private static func pinBody() -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 1, y: 6))
        p.line(to: NSPoint(x: 12, y: 6))
        p.line(to: NSPoint(x: 12, y: 7))
        p.curve(to: NSPoint(x: 8, y: 11), controlPoint1: NSPoint(x: 12, y: 9.5), controlPoint2: NSPoint(x: 9, y: 10))
        p.line(to: NSPoint(x: 8, y: 12))
        p.line(to: NSPoint(x: 10, y: 14))
        p.line(to: NSPoint(x: 10, y: 16))
        p.line(to: NSPoint(x: 3, y: 16))
        p.line(to: NSPoint(x: 3, y: 14))
        p.line(to: NSPoint(x: 5, y: 12))
        p.line(to: NSPoint(x: 5, y: 11))
        p.curve(to: NSPoint(x: 1, y: 7), controlPoint1: NSPoint(x: 4, y: 10), controlPoint2: NSPoint(x: 1, y: 9.5))
        p.close()
        return p
    }

    /// A four-point star with thin, curved-in arms.
    private static func sparkle(center c: NSPoint, radius r: CGFloat) -> NSBezierPath {
        let k = r * 0.18
        let p = NSBezierPath()
        p.move(to: NSPoint(x: c.x, y: c.y + r))
        for (tip, dx, dy) in [(NSPoint(x: c.x + r, y: c.y), k, k), (NSPoint(x: c.x, y: c.y - r), k, -k),
                              (NSPoint(x: c.x - r, y: c.y), -k, -k), (NSPoint(x: c.x, y: c.y + r), -k, k)] {
            let cp = NSPoint(x: c.x + dx, y: c.y + dy)
            p.curve(to: tip, controlPoint1: cp, controlPoint2: cp)
        }
        p.close()
        return p
    }
}
