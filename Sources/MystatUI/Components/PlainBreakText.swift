import AppKit
import MystatCore
import SwiftUI

/// Multi-line text without SwiftUI's line-break balancing. SwiftUI `Text` pushes words to the next line so the last line isn't a
/// single word, which makes an incident headline break earlier than designed, and there is no way to turn that off.
/// Used only for the two incident headlines where the difference shows.
/// Layout and drawing use the same `NSLayoutManager` (measured height matches the drawn height exactly); the line fragment padding is
/// 2 pt as in AppKit labels, and the text is drawn left-aligned.
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

    /// The layout manager holds the text storage weakly, so the three are carried together.
    struct Laid { let storage: NSTextStorage; let layout: NSLayoutManager; let container: NSTextContainer }

    /// Placed so the padding extends beyond the width: drawing stays left-aligned and line breaks match AppKit labels.
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

    /// Same style as `Headline`: emphasized part in the level color, same letter spacing and line spacing.
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

    /// Incident card title in the sidebar: 12.5 pt, weight 600.
    static func sideIncident(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: Theme.Fonts.sf(12.5, wght: 600),
            .foregroundColor: NSColor(Theme.ink),
            .paragraphStyle: paragraph(lineSpacing: 2),
        ])
    }

    /// Lines, using the same layout as drawing (for tests and verification).
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
