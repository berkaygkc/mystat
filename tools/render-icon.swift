// Renders the app icon the way Finder shows it (system squircle mask, edge highlight, shadow) to a transparent PNG.
// Usage: swift tools/render-icon.swift <path/to/mystat.app> <out.png> [size=512]
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: render-icon.swift <app> <out.png> [size]"); exit(64) }
let side = CGFloat(Double(args.count > 3 ? args[3] : "512") ?? 512)
let icon = NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: args[1]).path)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
