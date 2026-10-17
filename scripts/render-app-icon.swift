import AppKit

// Vector artwork for Finder/Dock. The same rectangle/crescent geometry as
// the menu-bar template, with a macOS-style app-icon background and no stand.
func drawIcon() {
    let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864),
                            xRadius: 192, yRadius: 192)
    let top = NSColor(calibratedRed: 0.18, green: 0.40, blue: 0.78, alpha: 1)
    let bottom = NSColor(calibratedRed: 0.055, green: 0.12, blue: 0.27, alpha: 1)
    NSGradient(starting: bottom, ending: top)!.draw(in: tile, angle: 65)

    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: 192, yBy: 224)
    transform.scale(by: 32)
    transform.concat()
    NSColor.white.setStroke()
    NSColor.white.setFill()
    let frame = NSBezierPath(roundedRect: NSRect(x: 1, y: 2, width: 18, height: 14),
                             xRadius: 2.2, yRadius: 2.2)
    frame.lineWidth = 1.6
    frame.stroke()
    // Join the two circle arcs directly, avoiding antialiased clipping seams.
    let outer = NSPoint(x: 10, y: 9), inner = NSPoint(x: 12.275, y: 11.175)
    let r: CGFloat = 4.4, innerRadius: CGFloat = 4.175
    let dx = inner.x - outer.x, dy = inner.y - outer.y
    let distance = sqrt(dx * dx + dy * dy)
    let along = (r * r - innerRadius * innerRadius + distance * distance) / (2 * distance)
    let perpendicular = sqrt(r * r - along * along)
    let base = NSPoint(x: outer.x + along * dx / distance, y: outer.y + along * dy / distance)
    let upper = NSPoint(x: base.x - perpendicular * dy / distance, y: base.y + perpendicular * dx / distance)
    let lower = NSPoint(x: base.x + perpendicular * dy / distance, y: base.y - perpendicular * dx / distance)
    func angle(_ point: NSPoint, _ center: NSPoint) -> CGFloat {
        atan2(point.y - center.y, point.x - center.x) * 180 / .pi
    }
    let crescent = NSBezierPath()
    crescent.appendArc(withCenter: outer, radius: r, startAngle: angle(upper, outer),
                       endAngle: angle(lower, outer), clockwise: false)
    crescent.appendArc(withCenter: inner, radius: innerRadius, startAngle: angle(lower, inner),
                       endAngle: angle(upper, inner), clockwise: true)
    crescent.close()
    crescent.fill()
    NSGraphicsContext.restoreGraphicsState()
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        drawIcon()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let file = directory.appendingPathComponent("icon_\(base)x\(base)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: file)
    }
}
