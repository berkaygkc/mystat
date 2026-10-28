import AppKit
import CoreText
import QuartzCore

/// Bir balon etiketinin bitmap'i (mockup `.bm-l`): ad 650 ağırlık ve satır kutusu 1,15·fs, 2 pt boşluk,
/// boyut 0,78·fs 550 ağırlık; iki katmanlı hale gölgesi; WebKit'in `-webkit-font-smoothing: antialiased`'ı gibi
/// yazı yumuşatması kapalı. Görüntü her yanda `pad` kadar hale payı taşır; merkezi kutunun merkezidir.
struct BubbleLabelImage {
    static let pad = 16.0
    let image: CGImage
    /// Nokta cinsinden, pay dahil.
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

        // Taban çizgileri (CG'de y yukarı). CSS yarım satır aralığı: glif kutusu satır kutusunun ortasında.
        let top = H - pad
        var lines: [(line: CTLine, x: Double, y: Double)] = []
        if let nl = nameLine {
            let asc = Double(nameFont.ascender), desc = Double(-nameFont.descender)
            lines.append((nl, pad + (boxW - width(nl)) / 2, top - ((nameH - (asc + desc)) / 2 + asc)))
        }
        let sizeTop = top - nameH - gap
        lines.append((sizeLine, pad + (boxW - width(sizeLine)) / 2, sizeTop - (Double(sizeFont.leading) / 2 + Double(sizeFont.ascender))))

        // Hale: metin tuvalin dışına çizilir, yalnızca gölgesi yerine düşer (metin iki kez çizilip kalınlaşmasın).
        let shift = W + 40
        let halo: [(dy: Double, blur: Double, color: NSColor)] = dark
            ? [(1, 3, NSColor(white: 0, alpha: 0.55)), (0, 14, NSColor(white: 0, alpha: 0.35))]
            : [(1, 2, NSColor(white: 1, alpha: 0.7)), (0, 12, NSColor(white: 1, alpha: 0.45))]
        for h in halo {
            ctx.saveGState()
            // Gölge ofseti cihaz pikselinde; CSS'teki 1 px aşağı = CG'de −y.
            ctx.setShadow(offset: CGSize(width: -shift * scale, height: -h.dy * scale), blur: h.blur * scale, color: h.color.cgColor)
            for l in lines { ctx.textPosition = CGPoint(x: l.x + shift, y: l.y); CTLineDraw(l.line, ctx) }
            ctx.restoreGState()
        }
        for l in lines { ctx.textPosition = CGPoint(x: l.x, y: l.y); CTLineDraw(l.line, ctx) }
        return BubbleLabelImage(image: ctx.makeImage()!, size: CGSize(width: W, height: H))
    }
}

/// Canlı etiket katmanı: metin yalnızca değişince yeniden çizilir; karede konum, opaklık ve ölçek
/// CA özelliği olarak güncellenir (SwiftUI düzeni yok) ve Metal karesiyle aynı işlemde sunulur.
final class BubbleLabelsView: NSView {
    private let root = CALayer()
    private struct Entry { let layer: CALayer; var key: String; var label: BubbleLabel? }
    private var entries: [String: Entry] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = root          // katman barındıran görünüm: alt katmanlar bizim
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
