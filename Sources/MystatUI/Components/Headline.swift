import MystatCore
import SwiftUI

/// Önce cümle başlığı. `.emphasized` işaretli kısım seviye rengine boyanır; `soft` kısmı soluk tonda.
public struct Headline: View {
    let title: AttributedString
    let soft: String?
    let size: CGFloat
    let level: Level

    public init(_ title: AttributedString, soft: String? = nil, size: CGFloat = 28, level: Level = .crit) {
        self.title = title; self.soft = soft; self.size = size; self.level = level
    }

    public init(_ title: String, soft: String? = nil, size: CGFloat = 28) {
        self.init(AttributedString(title), soft: soft, size: size, level: .ok)
    }

    public var body: some View {
        var t = AttributedString()
        for run in title.runs {
            var part = AttributedString(title[run.range].characters)
            // Önceden rengi verilmiş parçalar (ör. soluk birimler) korunur.
            part.foregroundColor = run.inlinePresentationIntent == .emphasized ? Theme.levelColor(level) : (title[run.range].foregroundColor ?? Theme.ink)
            t += part
        }
        if let soft {
            var s = AttributedString(" " + soft)
            s.foregroundColor = Theme.ink3
            s.font = Theme.Fonts.headline(size).weight(.medium)
            t += s
        }
        return Text(t)
            .font(Theme.Fonts.headline(size)).tracking(-size * (size > 25 ? 0.03 : 0.025))
            .lineSpacing(size * 0.15 - 2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
