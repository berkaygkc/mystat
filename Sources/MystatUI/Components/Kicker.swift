import MystatCore
import SwiftUI

/// Small uppercase kicker label and status dot ("● NOW").
public struct Kicker: View {
    let text: String
    let level: Level
    let pulsing: Bool
    let tintText: Bool

    /// `tintText`: in the monitor the incident label's text is tinted too; in the panel only the dot.
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
