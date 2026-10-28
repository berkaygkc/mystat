import AppKit
import MystatCore

/// Menü çubuğundaki tek blok: iki katlı metrikler + ağ + saat (tarz B). Tıklamalar alttaki düğmeye geçer.
final class StatusBlockView: NSView {
    var model: StatusBlockModel { didSet { if model != oldValue { beginAlertTransition(from: oldValue.alert); needsDisplay = true } } }
    /// Kaybolma geçişi bitip uyarı yeri boşalınca (uzunluk yeniden hesaplansın diye).
    var onLayoutChange: (() -> Void)?
    /// Kaybolurken hâlâ çizilen uyarı.
    private var ghost: StatusMetric?
    private var transition: (kind: StatusBlockLayout.AlertTransition, start: CFTimeInterval)?
    private var ticker: Timer?

    /// Çizilen ve uzunluğu belirleyen model: kaybolan uyarı geçiş süresince yerinde kalır.
    var drawnModel: StatusBlockModel {
        guard model.alert == nil, let g = ghost else { return model }
        var m = model
        m.alert = g
        return m
    }
    var highlighted = false { didSet { if highlighted != oldValue { needsDisplay = true } } }
    private var hovering = false { didSet { if hovering != oldValue { needsDisplay = true } } }

    init(model: StatusBlockModel) {
        self.model = model
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // MARK: - Uyarı geçişi (spec §4; mockup `popin`). Zamanlayıcı yalnızca geçiş süresince çalışır.

    private func beginAlertTransition(from old: StatusMetric?) {
        let new = model.alert
        guard old?.label != new?.label else { return }   // aynı uyarının değeri değişti: geçiş yok
        if new != nil { ghost = nil; transition = (.appear, CACurrentMediaTime()) }
        else { ghost = old; transition = (.disappear, CACurrentMediaTime()) }
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stepTransition() }
        }
    }

    private func stepTransition() {
        needsDisplay = true
        guard let tr = transition, !StatusBlockLayout.alertAnimationDone(tr.kind, elapsed: CACurrentMediaTime() - tr.start) else {
            let ended = transition?.kind
            transition = nil
            ticker?.invalidate()
            ticker = nil
            if ended == .disappear { ghost = nil; onLayoutChange?() }
            return
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    // MARK: - Yazı tipleri

    static let labelFont = NSFont.systemFont(ofSize: StatusBlockLayout.labelSize, weight: .semibold)
    static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: StatusBlockLayout.valueSize, weight: .semibold)
    static let netFont = NSFont.monospacedDigitSystemFont(ofSize: StatusBlockLayout.netSize, weight: .semibold)
    static let dateFont = NSFont.monospacedDigitSystemFont(ofSize: StatusBlockLayout.dateSize, weight: .medium)
    static let timeFont = NSFont.monospacedDigitSystemFont(ofSize: StatusBlockLayout.timeSize, weight: .semibold)
    static let labelKern: CGFloat = 0.6   // 0,07 em

    static func font(_ size: CGFloat) -> NSFont {
        switch size {
        case StatusBlockLayout.labelSize: labelFont
        case StatusBlockLayout.netSize: netFont
        case StatusBlockLayout.dateSize: dateFont
        case StatusBlockLayout.timeSize: timeFont
        default: valueFont
        }
    }

    /// Genişlikler çoğunlukla sabit şablonlardan ("%100", "88:88:88"…) gelir; her çizimde yeniden ölçülmesin.
    private static var widths: [String: CGFloat] = [:]

    static func measure(_ s: String, _ size: CGFloat, _ bold: Bool) -> CGFloat {
        let key = "\(size)|\(s)"
        if let w = widths[key] { return w }
        var attrs: [NSAttributedString.Key: Any] = [.font: font(size)]
        if size == StatusBlockLayout.labelSize { attrs[.kern] = labelKern }
        let w = ceil(NSAttributedString(string: s, attributes: attrs).size().width)
        if widths.count > 256 { widths.removeAll() }
        widths[key] = w
        return w
    }

    // MARK: - Çizim

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if hovering || highlighted {
            let r = bounds.insetBy(dx: 0, dy: max(0, (bounds.height - 26) / 2))
            (dark ? NSColor.white.withAlphaComponent(0.22) : NSColor.black.withAlphaComponent(0.08)).setFill()
            NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7).fill()
        }
        var x = StatusBlockLayout.blockPadding
        let model = drawnModel
        for (part, w) in StatusBlockLayout.parts(model, measure: Self.measure) {
            if part == .clock { x += StatusBlockLayout.clockGap }
            let box = NSRect(x: x, y: 0, width: w, height: bounds.height)
            switch part {
            case .alert: if let a = model.alert { drawAlert(a, in: box) }
            case .metric(let i): drawMetric(model.metrics[i], in: box)
            case .net: drawTwoLines(top: arrowed(model.down), bottom: arrowed(model.up), topFont: Self.netFont, bottomFont: Self.netFont, in: box, topAlpha: 1)
            case .clock: drawTwoLines(top: NSAttributedString(string: model.date), bottom: NSAttributedString(string: model.time),
                                      topFont: Self.dateFont, bottomFont: Self.timeFont, in: box, topAlpha: 0.8)
            }
            x += w + StatusBlockLayout.gap
        }
    }

    /// Geçiş sürerken uyarı grup opaklığı, kayma ve ölçekle çizilir.
    private func drawAlert(_ a: StatusMetric, in box: NSRect) {
        guard let tr = transition, let ctx = NSGraphicsContext.current?.cgContext else { drawMetric(a, in: box); return }
        let ap = StatusBlockLayout.alertAppearance(tr.kind, elapsed: CACurrentMediaTime() - tr.start)
        ctx.saveGState()
        ctx.setAlpha(ap.opacity)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.translateBy(x: box.midX + ap.dx, y: box.midY)
        ctx.scaleBy(x: ap.scale, y: ap.scale)
        ctx.translateBy(x: -box.midX, y: -box.midY)
        drawMetric(a, in: box)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private func lineHeight(_ f: NSFont) -> CGFloat { ceil(f.ascender - f.descender) * 0.98 }

    private func drawMetric(_ m: StatusMetric, in box: NSRect) {
        let lh = lineHeight(Self.labelFont), vh = lineHeight(Self.valueFont)
        let y0 = (bounds.height - lh - vh) / 2
        var fg = NSColor.labelColor
        if m.level != .ok {
            let pill = m.level == .crit ? NSColor(srgbRed: 1, green: 59 / 255, blue: 48 / 255, alpha: 0.9)
                                        : NSColor(srgbRed: 1, green: 159 / 255, blue: 10 / 255, alpha: 0.88)
            pill.setFill()
            NSBezierPath(roundedRect: NSRect(x: box.minX, y: y0 - 1, width: box.width, height: lh + vh + 2), xRadius: 5, yRadius: 5).fill()
            fg = .white
        }
        NSAttributedString(string: m.label, attributes: [.font: Self.labelFont, .kern: Self.labelKern,
                                                         .foregroundColor: fg.withAlphaComponent(m.level == .ok ? 0.62 : 0.9)])
            .draw(at: NSPoint(x: box.minX + StatusBlockLayout.metricPadding, y: y0))
        NSAttributedString(string: m.value, attributes: [.font: Self.valueFont, .foregroundColor: fg])
            .draw(at: NSPoint(x: box.minX + StatusBlockLayout.metricPadding, y: y0 + lh))
    }

    private func arrowed(_ s: String) -> NSAttributedString {
        let out = NSMutableAttributedString(string: s, attributes: [.font: Self.netFont, .foregroundColor: NSColor.labelColor])
        if let first = s.first, first == "↓" || first == "↑" {
            out.addAttributes([.foregroundColor: NSColor.labelColor.withAlphaComponent(0.6),
                               .font: NSFont.monospacedDigitSystemFont(ofSize: StatusBlockLayout.netSize, weight: .medium)],
                              range: NSRange(location: 0, length: 1))
        }
        return out
    }

    /// Sağa yaslı iki satır (ağ ve saat).
    private func drawTwoLines(top: NSAttributedString, bottom: NSAttributedString, topFont: NSFont, bottomFont: NSFont, in box: NSRect, topAlpha: CGFloat) {
        let th = lineHeight(topFont), bh = lineHeight(bottomFont)
        let y0 = (bounds.height - th - bh) / 2
        let t = NSMutableAttributedString(attributedString: top)
        let b = NSMutableAttributedString(attributedString: bottom)
        if t.length > 0, t.attribute(.font, at: 0, effectiveRange: nil) == nil {
            t.addAttributes([.font: topFont, .foregroundColor: NSColor.labelColor.withAlphaComponent(topAlpha)], range: NSRange(location: 0, length: t.length))
        }
        if b.length > 0, b.attribute(.font, at: 0, effectiveRange: nil) == nil {
            b.addAttributes([.font: bottomFont, .foregroundColor: NSColor.labelColor], range: NSRange(location: 0, length: b.length))
        }
        let right = box.maxX - StatusBlockLayout.metricPadding
        t.draw(at: NSPoint(x: right - t.size().width, y: y0))
        b.draw(at: NSPoint(x: right - b.size().width, y: y0 + th))
    }
}
