import AppKit
import MystatCore
import SwiftUI

/// Çok satırlı metin, satır sonunda "itme" (push-out) kapalı. SwiftUI `Text` son satırı tek kelime bırakmamak için
/// kelimeleri aşağı itiyor ("Claude Code / işlemciyi zorluyor."); mockup "Claude Code işlemciyi / zorluyor." kırıyor ve
/// SwiftUI bunu kapatmaya izin vermiyor. Yalnızca mockup'la farkın görüldüğü iki olay başlığında kullanılır.
/// Düzen ve çizim aynı `NSLayoutManager` ile (ölçülen yükseklik çizilenle birebir); satır kenar payı AppKit etiketlerindeki
/// gibi 2 pt, metin sola yaslı çizilir.
struct PlainBreakText: NSViewRepresentable {
    let text: NSAttributedString
    static let padding: CGFloat = 2

    final class View: NSView {
        var text = NSAttributedString() { didSet { needsDisplay = true } }
        override var isFlipped: Bool { true }
        override func draw(_ dirty: NSRect) {
            let t = PlainBreakText.layout(text, width: bounds.width)
            t.layout.drawGlyphs(forGlyphRange: t.layout.glyphRange(for: t.container), at: NSPoint(x: -PlainBreakText.padding, y: 0))
        }
    }

    func makeNSView(context: Context) -> View { View() }

    func updateNSView(_ v: View, context: Context) {
        if v.text != text { v.text = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView v: View, context: Context) -> CGSize? {
        let w = proposal.width ?? 10_000
        let t = Self.layout(text, width: w)
        return CGSize(width: w, height: ceil(t.layout.usedRect(for: t.container).height))
    }

    /// Düzenleyici metin deposunu zayıf tutar: üçü birlikte taşınır.
    struct Laid { let storage: NSTextStorage; let layout: NSLayoutManager; let container: NSTextContainer }

    /// Kenar payı genişliğin dışına taşacak biçimde konur: çizim sola yaslı kalır, satır kırılımı AppKit etiketleriyle aynı.
    static func layout(_ s: NSAttributedString, width: CGFloat) -> Laid {
        let storage = NSTextStorage(attributedString: s)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: max(1, width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = padding
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        return Laid(storage: storage, layout: layout, container: container)
    }

    static func paragraph(lineSpacing: CGFloat) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = lineSpacing
        p.lineBreakStrategy = []
        p.lineBreakMode = .byWordWrapping
        return p
    }

    /// `Headline` ile aynı biçim: vurgulu kısım seviye renginde, harf aralığı ve satır aralığı aynı.
    static func headline(_ title: AttributedString, size: CGFloat, level: Level) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [
            .font: Theme.Fonts.headlineNSFont(size),
            .kern: -size * (size > 25 ? 0.03 : 0.025),
            .paragraphStyle: paragraph(lineSpacing: size * 0.15 - 2),
        ]
        for run in title.runs {
            var a = base
            a[.foregroundColor] = NSColor(run.inlinePresentationIntent == .emphasized ? Theme.levelColor(level) : Theme.ink)
            out.append(NSAttributedString(string: String(title[run.range].characters), attributes: a))
        }
        return out
    }

    /// Kenar menüsündeki olay kartı (mockup `.side-inc .t`): 12,5 pt, 600 ağırlık.
    static func sideIncident(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: Theme.Fonts.sf(12.5, wght: 600),
            .foregroundColor: NSColor(Theme.ink),
            .paragraphStyle: paragraph(lineSpacing: 2),
        ])
    }

    /// Satırlar, çizimle aynı düzenle (testler ve doğrulama için).
    static func lines(_ s: NSAttributedString, width: CGFloat) -> [String] {
        let t = layout(s, width: width), layout = t.layout
        var out: [String] = []
        var index = 0
        while index < layout.numberOfGlyphs {
            var range = NSRange()
            layout.lineFragmentRect(forGlyphAt: index, effectiveRange: &range)
            out.append((s.string as NSString).substring(with: layout.characterRange(forGlyphRange: range, actualGlyphRange: nil)))
            index = NSMaxRange(range)
        }
        return out
    }
}
