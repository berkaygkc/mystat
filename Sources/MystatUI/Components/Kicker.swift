import MystatCore
import SwiftUI

/// Küçük büyük harfli üst etiket ve durum noktası ("● ŞU AN").
public struct Kicker: View {
    let text: String
    let level: Level
    let pulsing: Bool
    let tintText: Bool

    /// `tintText`: monitörde olay etiketinin yazısı da renklenir; panelde yalnızca nokta.
    public init(_ text: String, level: Level = .ok, pulsing: Bool = false, tintText: Bool = true) {
        self.text = text; self.level = level; self.pulsing = pulsing; self.tintText = tintText
    }

    public var body: some View {
        HStack(spacing: 7) {
            PulseDot(color: level == .ok ? Theme.green : Theme.levelColor(level), pulsing: pulsing)
                .frame(width: 6, height: 6)
            Text(text)
                .font(Theme.Fonts.kicker()).tracking(1.68)
                .foregroundStyle(level == .ok || !tintText ? Theme.ink3 : Theme.levelColor(level))
        }
    }
}
