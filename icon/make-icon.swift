// Renders the app icon, icon/icon.png: a white pin with sparkles on an orange
// rounded square, with a lighter strip down the left side for the pinned
// window's strip. Uses the standard macOS icon grid.
//
//   swift icon/make-icon.swift
//
// make-app.sh turns the PNG into AppIcon.icns, so rerun this only to change
// the design. To use your own artwork, replace icon/icon.png with any
// 1024x1024 PNG.
import AppKit

let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icons are an 824pt square with a 185pt corner radius on a 1024 canvas;
// the margin leaves room for the shadow.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 24
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(
    starting: NSColor(srgbRed: 1.00, green: 0.62, blue: 0.20, alpha: 1),
    ending: NSColor(srgbRed: 0.93, green: 0.33, blue: 0.16, alpha: 1)
)!.draw(in: shape, angle: -90)

func symbol(_ name: String, _ pointSize: CGFloat, _ color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
}

// Drawn centred on a point, turned by the given angle.
func draw(_ image: NSImage, at center: NSPoint, angle: CGFloat = 0) {
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform()
    t.translateX(by: center.x, yBy: center.y)
    t.rotate(byDegrees: angle)
    t.concat()
    let s = image.size
    image.draw(in: NSRect(x: -s.width / 2, y: -s.height / 2, width: s.width, height: s.height))
    NSGraphicsContext.restoreGraphicsState()
}

shape.addClip()

// The strip a pinned window holds, down the left side of the tile.
NSColor.white.withAlphaComponent(0.22).setFill()
NSRect(x: tile.minX, y: tile.minY, width: 250, height: tile.height).fill()

// The pin, tipped over a little as if just pushed in, with a shadow under it.
NSGraphicsContext.saveGraphicsState()
let pinShadow = NSShadow()
pinShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
pinShadow.shadowOffset = NSSize(width: 8, height: -14)
pinShadow.shadowBlurRadius = 20
pinShadow.set()
draw(symbol("pin.fill", 400, .white), at: NSPoint(x: tile.midX + 10, y: tile.midY - 10), angle: 30)
NSGraphicsContext.restoreGraphicsState()

// Sparkles: a big one and a small one at the top right.
let gold = NSColor(srgbRed: 1.00, green: 0.93, blue: 0.62, alpha: 1)
draw(symbol("sparkle", 190, gold), at: NSPoint(x: tile.maxX - 175, y: tile.maxY - 175))
draw(symbol("sparkle", 95, gold), at: NSPoint(x: tile.maxX - 310, y: tile.maxY - 105))

NSGraphicsContext.current = nil
let out = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent().appendingPathComponent("icon.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
