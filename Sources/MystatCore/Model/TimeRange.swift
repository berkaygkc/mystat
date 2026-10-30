import Foundation

/// Chart time ranges and navigation hint texts.
public enum TimeRange: CaseIterable, Sendable, Hashable {
    case m10, h1, h24, d7

    public var title: String {
        L10n.t("range.\(key)")
    }

    public var pointCount: Int {
        switch self { case .m10: 120; case .h1: 120; case .h24: 144; case .d7: 168 }
    }

    /// Duration between two points (s).
    public var step: TimeInterval {
        switch self { case .m10: 5; case .h1: 30; case .h24: 600; case .d7: 3600 }
    }

    public var axisLabels: [String] {
        L10n.t("range.\(key).axis").components(separatedBy: "|")
    }

    private var key: String { switch self { case .m10: "m10"; case .h1: "h1"; case .h24: "h24"; case .d7: "d7" } }

    public func hoverLabel(index: Int, now: Date, calendar: Calendar) -> String {
        let back = pointCount - 1 - index
        switch self {
        case .m10, .h1:
            let s = back * Int(step)
            if s == 0 { return L10n.t("time.now") }
            if s < 60 { return L10n.t("time.secondsAgo", ["s": String(s)]) }
            return s % 60 == 0 ? L10n.t("time.minutesAgo", ["m": String(s / 60)]) : L10n.t("time.minutesSecondsAgo", ["m": String(s / 60), "s": String(s % 60)])
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

    /// Day names in the selected language (starting from Sunday).
    static var dayNames: [String] { DateFormatter.weekdays(Fmt.locale) }
}
