import AppKit

let px = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: px, height: px)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(deviceRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// macOS icon grid: 824pt rounded square centred in 1024, with a soft drop shadow.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
rgb(20, 40, 110).setFill()
shape.fill()
ctx.restoreGState()

// Background: deep blueprint blue, lighter toward the top-left.
ctx.saveGState()
shape.addClip()
NSGradient(colorsAndLocations: (rgb(64, 190, 255), 0), (rgb(28, 110, 240), 0.45), (rgb(40, 40, 160), 1))!
    .draw(in: body, angle: -60)

// Blueprint grid.
rgb(255, 255, 255, 0.07).setStroke()
let grid = NSBezierPath()
grid.lineWidth = 3
var p: CGFloat = 100 + 103
while p < 924 {
    grid.move(to: NSPoint(x: p, y: 100)); grid.line(to: NSPoint(x: p, y: 924))
    grid.move(to: NSPoint(x: 100, y: p)); grid.line(to: NSPoint(x: 924, y: p))
    p += 103
}
grid.stroke()

// Soft glow behind the tool head.
NSGradient(colors: [rgb(255, 255, 255, 0.28), rgb(255, 255, 255, 0)])!
    .draw(fromCenter: NSPoint(x: 600, y: 610), radius: 0, toCenter: NSPoint(x: 600, y: 610), radius: 420, options: [])

// Sweep arc: the "cleaned" path, fading out behind the hammer.
ctx.saveGState()
ctx.setLineCap(.round)
for (i, alpha) in [0.10, 0.16, 0.24].enumerated() {
    let radius = CGFloat(300 + i * 62)
    let arc = NSBezierPath()
    arc.appendArc(withCenter: NSPoint(x: 330, y: 300), radius: radius, startAngle: 12, endAngle: 78)
    arc.lineWidth = 26
    arc.lineCapStyle = .round
    rgb(255, 255, 255, alpha).setStroke()
    arc.stroke()
}
ctx.restoreGState()

// Hammer, with a drop shadow so it sits above the grid.
func symbol(_ name: String, points: CGFloat, color: NSColor, weight: NSFont.Weight = .bold) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: points, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
}
let hammer = symbol("hammer.fill", points: 430, color: .white)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 30, color: rgb(10, 20, 80, 0.55).cgColor)
let hw = hammer.size.width, hh = hammer.size.height
hammer.draw(in: NSRect(x: 512 - hw / 2 - 28, y: 512 - hh / 2 - 28, width: hw, height: hh))
ctx.restoreGState()

// Sparkles: the "pimp".
func sparkle(at c: NSPoint, size s: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    let k = s * 0.16   // waist of the four-point star
    path.move(to: NSPoint(x: c.x, y: c.y + s))
    path.curve(to: NSPoint(x: c.x + s, y: c.y), controlPoint1: NSPoint(x: c.x + k, y: c.y + k), controlPoint2: NSPoint(x: c.x + k, y: c.y + k))
    path.curve(to: NSPoint(x: c.x, y: c.y - s), controlPoint1: NSPoint(x: c.x + k, y: c.y - k), controlPoint2: NSPoint(x: c.x + k, y: c.y - k))
    path.curve(to: NSPoint(x: c.x - s, y: c.y), controlPoint1: NSPoint(x: c.x - k, y: c.y - k), controlPoint2: NSPoint(x: c.x - k, y: c.y - k))
    path.curve(to: NSPoint(x: c.x, y: c.y + s), controlPoint1: NSPoint(x: c.x - k, y: c.y + k), controlPoint2: NSPoint(x: c.x - k, y: c.y + k))
    path.close()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.5, color: rgb(255, 210, 80, 0.8).cgColor)
    color.setFill()
    path.fill()
    ctx.restoreGState()
}
sparkle(at: NSPoint(x: 742, y: 742), size: 96, color: rgb(255, 222, 89))
sparkle(at: NSPoint(x: 838, y: 610), size: 46, color: rgb(255, 236, 150))
sparkle(at: NSPoint(x: 612, y: 838), size: 38, color: rgb(255, 236, 150))

// Glass highlight along the top edge.
NSGradient(colors: [rgb(255, 255, 255, 0.22), rgb(255, 255, 255, 0)])!
    .draw(in: NSRect(x: 100, y: 620, width: 824, height: 304), angle: -90)
ctx.restoreGState()

// Thin inner rim.
rgb(255, 255, 255, 0.18).setStroke()
let rim = NSBezierPath(roundedRect: body.insetBy(dx: 3, dy: 3), xRadius: 183, yRadius: 183)
rim.lineWidth = 6
rim.stroke()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
