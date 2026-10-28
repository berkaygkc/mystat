import Foundation

/// Grafik zaman aralıkları ve gezinti ipucu metinleri (mockup'taki `timeLabel`, `xLabels`).
public enum TimeRange: CaseIterable, Sendable, Hashable {
    case m10, h1, h24, d7

    public var title: String {
        switch self { case .m10: "10 dk"; case .h1: "1 sa"; case .h24: "24 sa"; case .d7: "7 gün" }
    }

    public var pointCount: Int {
        switch self { case .m10: 120; case .h1: 120; case .h24: 144; case .d7: 168 }
    }

    /// İki nokta arası süre (sn).
    public var step: TimeInterval {
        switch self { case .m10: 5; case .h1: 30; case .h24: 600; case .d7: 3600 }
    }

    public var axisLabels: [String] {
        switch self {
        case .m10: ["10 dk önce", "5 dk", "şimdi"]
        case .h1: ["1 sa önce", "30 dk", "şimdi"]
        case .h24: ["24 sa önce", "12 sa", "şimdi"]
        case .d7: ["7 gün önce", "3 gün", "şimdi"]
        }
    }

    public func hoverLabel(index: Int, now: Date, calendar: Calendar) -> String {
        let back = pointCount - 1 - index
        switch self {
        case .m10, .h1:
            let s = back * Int(step)
            if s == 0 { return "şimdi" }
            if s < 60 { return "\(s) sn önce" }
            return s % 60 == 0 ? "\(s / 60) dk önce" : "\(s / 60) dk \(s % 60) sn önce"
        case .h24:
            let d = now.addingTimeInterval(-Double(back) * step)
            let c = calendar.dateComponents([.hour, .minute], from: d)
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        case .d7:
            let d = now.addingTimeInterval(-Double(back) * step)
            let c = calendar.dateComponents([.hour, .weekday], from: d)
            return "\(Self.dayNames[(c.weekday ?? 1) - 1]) \(String(format: "%02d", c.hour ?? 0)):00"
        }
    }

    static let dayNames = ["Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"]
}
