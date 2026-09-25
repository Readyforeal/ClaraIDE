import AppKit

// Static compatibility icon for machines without Xcode's Icon Composer compiler.
// Keep the original .icon package alongside this output for native layered builds.
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
let rendered = CommandLine.arguments.contains("--rendered")
guard let artwork = NSImage(contentsOf: source) else { fatalError("Cannot read icon artwork") }
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let size = CGFloat(pixels)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        let rect = NSRect(x: size * 0.10, y: size * 0.10, width: size * 0.80, height: size * 0.80)
        let tile = NSBezierPath(roundedRect: rect, xRadius: size * 0.18, yRadius: size * 0.18)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
        shadow.shadowBlurRadius = size * 0.025
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
        shadow.set()
        if rendered {
            artwork.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NSColor.white.setFill(); tile.fill()
            NSGraphicsContext.restoreGraphicsState()
            tile.addClip()
            artwork.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let data = bitmap.representation(using: .png, properties: [:])!
        try data.write(to: destination.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
