import AppKit
import MystatCore
import MystatTestSupport
import Testing
@testable import MystatUI

@MainActor @Suite(.language("tr")) struct PlainBreakTextTests {
    /// SwiftUI son satırı tek kelime bırakmamak için kelime itiyor ("Claude Code / işlemciyi zorluyor."); mockup
    /// "Claude Code işlemciyi / zorluyor." kırıyor. İtme kapalı metin mockup'taki gibi kırılmalı.
    @Test func breaksLikeMockup() {
        var title = AttributedString("Claude Code"); title.inlinePresentationIntent = .emphasized
        title += AttributedString(" işlemciyi zorluyor.")
        let s = PlainBreakText.headline(title, size: 23, level: .crit)
        let first = NSAttributedString(string: "Claude Code işlemciyi", attributes: s.attributes(at: 0, effectiveRange: nil)).size().width
        #expect(PlainBreakText.lines(s, width: first + 8) == ["Claude Code işlemciyi ", "zorluyor."])
    }

    @Test func headlineKeepsEmphasisColorAndFont() {
        var title = AttributedString("Claude Code"); title.inlinePresentationIntent = .emphasized
        title += AttributedString(" işlemciyi zorluyor.")
        let s = PlainBreakText.headline(title, size: 23, level: .crit)
        #expect(s.string == "Claude Code işlemciyi zorluyor.")
        let emph = s.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let rest = s.attribute(.foregroundColor, at: 13, effectiveRange: nil) as? NSColor
        #expect(emph != nil && rest != nil && emph != rest)
        #expect((s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 23)
    }

    /// Kenar menüsü kartı (iç genişlik 189): mockup gibi "Claude Code işlemciyi / zorluyor".
    @Test func sideCardBreaksLikeMockup() {
        #expect(PlainBreakText.lines(PlainBreakText.sideIncident("Claude Code işlemciyi zorluyor"), width: 189) == ["Claude Code işlemciyi ", "zorluyor"])
    }
}
