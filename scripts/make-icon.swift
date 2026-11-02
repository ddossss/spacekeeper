import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let p = CGFloat(pixels)
        NSColor(red: 0.03, green: 0.48, blue: 0.50, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.06, y: p * 0.06, width: p * 0.88, height: p * 0.88),
                     xRadius: p * 0.20, yRadius: p * 0.20).fill()
        for (offset, alpha) in [(0.0, 0.35), (0.16, 0.65), (0.32, 1.0)] {
            NSColor.white.withAlphaComponent(alpha).setFill()
            let y = p * (0.23 + offset)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: p * 0.22, y: y + p * 0.08))
            path.line(to: NSPoint(x: p * 0.5, y: y - p * 0.055))
            path.line(to: NSPoint(x: p * 0.78, y: y + p * 0.08))
            path.line(to: NSPoint(x: p * 0.5, y: y + p * 0.215))
            path.close(); path.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(filename))
    }
}
