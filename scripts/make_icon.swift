import AppKit

let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(srgbRed: 0.10, green: 0.38, blue: 0.74, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 256, height: 256), xRadius: 54, yRadius: 54).fill()
let text = "AP" as NSString
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 92, weight: .semibold), .foregroundColor: NSColor.white]
let size = text.size(withAttributes: attributes)
text.draw(at: NSPoint(x: (256 - size.width) / 2, y: (256 - size.height) / 2), withAttributes: attributes)
NSGraphicsContext.restoreGraphicsState()
let output = bitmap.converting(to: .sRGB, renderingIntent: .default)!
try output.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
