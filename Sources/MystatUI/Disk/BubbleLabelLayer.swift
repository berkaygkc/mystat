import AppKit
import CoreText
import QuartzCore

/// Bitmap of one bubble label: name at weight 650 with a 1.15·fs line box, 2 pt gap,
/// size at 0.78·fs weight 550; two-layer halo shadow; font smoothing is off, like WebKit's `-webkit-font-smoothing: antialiased`.
/// The image carries `pad` of halo margin on every side; its center is the box's center.
struct BubbleLabelImage {
    static let pad = 16.0
    let image: CGImage
    /// In points, including the padding.
    let size: CGSize

    @MainActor
    static func make(name: String?, size text: String, fontSize fs: Double, dark: Bool, scale: CGFloat) -> BubbleLabelImage {
        let ink = dark ? NSColor(srgbRed: 245 / 255, green: 245 / 255, blue: 247 / 255, alpha: 1) : NSColor(srgbRed: 29 / 255, green: 29 / 255, blue: 31 / 255, alpha: 1)
        let ink2 = dark ? NSColor(srgbRed: 235 / 255, green: 235 / 255, blue: 245 / 255, alpha: 0.70) : NSColor(srgbRed: 60 / 255, green: 60 / 255, blue: 67 / 255, alpha: 0.76)
        let nameFont = Theme.Fonts.sf(fs, wght: 650)
        let sizeFont = Theme.Fonts.sf(fs * 0.78, wght: 550, tabular: true)
        let nameLine = name.map {
            CTLineCreateWithAttributedString(NSAttributedString(string: $0, attributes: [.font: nameFont, .foregroundColor: ink, .kern: -0.01 * fs]))
        }
        let sizeLine = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: sizeFont, .foregroundColor: ink2]))
        func width(_ l: CTLine) -> Double { CTLineGetTypographicBounds(l, nil, nil, nil) }

        let nameH = nameLine == nil ? 0 : 1.15 * fs
        let gap = nameLine == nil ? 0 : 2.0
        let sizeH = Double(sizeFont.ascender - sizeFont.descender + sizeFont.leading)
        let boxW = max(nameLine.map(width) ?? 0, width(sizeLine))
        let W = boxW + 2 * pad, H = nameH + gap + sizeH + 2 * pad
        let pw = max(1, Int((W * scale).rounded())), ph = max(1, Int((H * scale).rounded()))
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)!
        ctx.scaleBy(x: scale, y: scale)
        ctx.setAllowsFontSmoothing(false)
        ctx.setShouldSmoothFonts(false)
        ctx.setShouldSubpixelPositionFonts(true)
        ctx.setShouldSubpixelQuantizeFonts(false)

        // Baselines (y is up in CG). CSS half-leading: the glyph box sits in the middle of the line box.
        let top = H - pad
        var lines: [(line: CTLine, x: Double, y: Double)] = []
        if let nl = nameLine {
            let asc = Double(nameFont.ascender), desc = Double(-nameFont.descender)
            lines.append((nl, pad + (boxW - width(nl)) / 2, top - ((nameH - (asc + desc)) / 2 + asc)))
        }
        let sizeTop = top - nameH - gap
        lines.append((sizeLine, pad + (boxW - width(sizeLine)) / 2, sizeTop - (Double(sizeFont.leading) / 2 + Double(sizeFont.ascender))))

        // Halo: the text is drawn off the canvas and only its shadow lands inside (so the text is not drawn twice and thickened).
        let shift = W + 40
        let halo: [(dy: Double, blur: Double, color: NSColor)] = dark
            ? [(1, 3, NSColor(white: 0, alpha: 0.55)), (0, 14, NSColor(white: 0, alpha: 0.35))]
            : [(1, 2, NSColor(white: 1, alpha: 0.7)), (0, 12, NSColor(white: 1, alpha: 0.45))]
        for h in halo {
            ctx.saveGState()
            // Shadow offset is in device pixels; CSS's 1 px down is −y in CG.
            ctx.setShadow(offset: CGSize(width: -shift * scale, height: -h.dy * scale), blur: h.blur * scale, color: h.color.cgColor)
            for l in lines { ctx.textPosition = CGPoint(x: l.x + shift, y: l.y); CTLineDraw(l.line, ctx) }
            ctx.restoreGState()
        }
        for l in lines { ctx.textPosition = CGPoint(x: l.x, y: l.y); CTLineDraw(l.line, ctx) }
        return BubbleLabelImage(image: ctx.makeImage()!, size: CGSize(width: W, height: H))
    }
}

/// Live label layer: text is redrawn only when it changes; per frame, position, opacity and scale
/// are updated as CA properties (no SwiftUI layout) and presented in the same transaction as the Metal frame.
final class BubbleLabelsView: NSView {
    private let root = CALayer()
    private struct Entry { let layer: CALayer; var key: String; var label: BubbleLabel? }
    private var entries: [String: Entry] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = root          // layer-hosting view: the sublayers are ours
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(_ labels: [BubbleLabel], dark: Bool) {
        let scale = window?.backingScaleFactor ?? 2
        let h = bounds.height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var live = Set<String>()
        for l in labels {
            live.insert(l.id)
            let key = "\(l.name ?? "")|\(l.size)|\(l.fontSize)|\(dark)|\(scale)"
            var e = entries[l.id] ?? {
                let ly = CALayer()
                root.addSublayer(ly)
                return Entry(layer: ly, key: "", label: nil)
            }()
            if e.key != key {
                let img = BubbleLabelImage.make(name: l.name, size: l.size, fontSize: l.fontSize, dark: dark, scale: scale)
                e.layer.contents = img.image
                e.layer.contentsScale = scale
                e.layer.bounds = CGRect(origin: .zero, size: img.size)
                e.key = key
            }
            if e.label != l || e.layer.position.y != h - l.y {
                e.layer.position = CGPoint(x: l.x, y: h - l.y)
                e.layer.opacity = Float(l.alpha)
                e.layer.setAffineTransform(CGAffineTransform(scaleX: l.scale, y: l.scale))
                e.label = l
            }
            entries[l.id] = e
        }
        for (id, e) in entries where !live.contains(id) {
            e.layer.removeFromSuperlayer()
            entries[id] = nil
        }
        CATransaction.commit()
    }
}
