// Draws Leftover's app icon: the usage ring on a dark rounded square.
//   swift Scripts/make-icon.swift <output-dir>   → AppIcon.iconset + icon_1024.png
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/icons", isDirectory: true)
let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func draw(_ size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size / 1024

    // macOS icon grid: an 824pt square with a 100pt margin.
    let rect = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(red: 0.12, green: 0.14, blue: 0.19, alpha: 1),
                        NSColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1)])!
        .draw(in: squircle, angle: -90)
    // A faint inner rim, for depth.
    NSColor.white.withAlphaComponent(0.06).setStroke()
    squircle.lineWidth = 3 * s
    squircle.stroke()

    // The usage ring: a dim track, and a green→mint arc with round caps.
    let center = CGPoint(x: 512 * s, y: 512 * s)
    let radius = 252 * s
    let width = 72 * s

    ctx.setLineCap(.round)
    ctx.setLineWidth(width)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // The arc: from the top, ~72% clockwise.
    let start = CGFloat.pi / 2                 // top (y is up)
    let fraction: CGFloat = 0.72
    let end = start - fraction * .pi * 2        // clockwise
    ctx.saveGState()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [NSColor(red: 0.18, green: 0.85, blue: 0.47, alpha: 1).cgColor,
                                       NSColor(red: 0.35, green: 0.95, blue: 0.70, alpha: 1).cgColor] as CFArray,
                              locations: [0, 1])!
    // Draw the arc as a mask and fill it with the gradient.
    ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(gradient, start: CGPoint(x: center.x - radius, y: center.y + radius),
                           end: CGPoint(x: center.x + radius, y: center.y - radius), options: [])
    ctx.restoreGState()

    // Inner red half ring: from the top, ~50% counter-clockwise.
    let innerRadius = 150 * s
    let innerWidth = 54 * s
    ctx.setLineWidth(innerWidth)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
    ctx.addArc(center: center, radius: innerRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    let redEnd = start + 0.5 * .pi * 2          // counter-clockwise
    ctx.saveGState()
    let redGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [NSColor(red: 0.98, green: 0.30, blue: 0.33, alpha: 1).cgColor,
                                          NSColor(red: 0.90, green: 0.18, blue: 0.22, alpha: 1).cgColor] as CFArray,
                                 locations: [0, 1])!
    ctx.addArc(center: center, radius: innerRadius, startAngle: start, endAngle: redEnd, clockwise: false)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(redGradient, start: CGPoint(x: center.x + innerRadius, y: center.y + innerRadius),
                           end: CGPoint(x: center.x - innerRadius, y: center.y - innerRadius), options: [])
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for base in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = draw(CGFloat(base * factor)).representation(using: .png, properties: [:])!
        try! data.write(to: iconset.appendingPathComponent(name))
    }
}
// A 1024px copy for previewing.
try! draw(1024).representation(using: .png, properties: [:])!
    .write(to: output.appendingPathComponent("icon_1024.png"))
