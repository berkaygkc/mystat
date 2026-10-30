import Foundation
import Synchronization

/// Number, percent, date and duration formats of the selected language.
public enum Fmt {
    /// `Locale` of the selected language (`_meta.locale`).
    public static var locale: Locale { L10n.current.locale }

    /// Time and date are always Gregorian (even if the region setting uses a Buddhist or Islamic calendar).
    public static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = locale
        c.timeZone = .current
        return c
    }

    /// Real data can contain NaN/inf; returns "—" instead of crashing.
    static let missing = "—"

    /// Percent as "%14" or "14%" depending on the language (`_meta.percent`), rounded to an integer.
    public static func pct(_ v: Double) -> String {
        guard v.isFinite else { return missing }
        let pattern = Localizer.shared.meta("percent", language: L10n.code) ?? "{value}%"
        return pattern.replacingOccurrences(of: "{value}", with: String(Int(v.rounded())))
    }

    /// "4,2"
    public static func dec1(_ v: Double) -> String {
        guard v.isFinite else { return missing }
        return v.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    /// "4.800"
    public static func int(_ v: Double) -> String { v.isFinite ? Int(v.rounded()).formatted(.number.locale(locale)) : missing }

    /// Core value; "<0,1" if greater than zero but below 0.05.
    public static func cores(_ v: Double) -> String { v > 0 && v < 0.05 ? "<" + dec1(0.1) : dec1(v) }

    /// Memory: integer for ≥ 10 GB, otherwise one decimal.
    public static func mem(_ gb: Double) -> String { (gb >= 10 ? int(gb) : dec1(gb)) + " GB" }

    /// Disk size (decimal units): GB → MB → KB.
    public static func size(_ gb: Double) -> String {
        guard gb.isFinite else { return missing }
        if gb >= 10 { return int(gb) + " GB" }
        if gb >= 1 { return dec1(gb) + " GB" }
        let mb = gb * 1000
        if mb >= 10 { return int(mb) + " MB" }
        if mb >= 1 { return dec1(mb) + " MB" }
        return int(max(1, gb * 1_000_000)) + " KB"
    }

    /// Uptime: "14 min", "2 h 14 min", "45 h", "3 days".
    public static func uptime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return missing }
        let m = Int(seconds / 60), h = m / 60
        if h < 1 { return L10n.t("unit.minutes", ["m": String(max(1, m))]) }
        if h < 10 { return m % 60 == 0 ? L10n.t("unit.hours", ["h": String(h)]) : L10n.t("unit.hoursMinutes", ["h": String(h), "m": String(m % 60)]) }
        if h < 72 { return L10n.t("unit.hours", ["h": String(h)]) }
        return L10n.plural("unit.days", h / 24)
    }

    /// Network rate number ("2,4"); the unit is written separately.
    public static func rate(_ mbps: Double) -> String { dec1(mbps) }

    /// Full date line, e.g. "Thursday, October 29, 2026" (`_meta.dateLine`); other languages use their own pattern.
    public static func dateLine(_ d: Date, calendar: Calendar = Fmt.calendar) -> String {
        let code = L10n.code
        let pattern = Localizer.shared.meta("dateLine", language: code) ?? "EEEE, MMMM d, y"
        let key = "\(code)|\(pattern)|\(calendar.identifier)|\(calendar.timeZone.identifier)"
        return dateFormatters.withLock { cache in
            let f = cache[key] ?? {
                let f = DateFormatter()
                f.locale = L10n.current.locale; f.calendar = calendar; f.timeZone = calendar.timeZone; f.dateFormat = pattern
                cache[key] = f
                return f
            }()
            return f.string(from: d)
        }
    }

    /// One formatter per language, pattern, calendar and time zone (the menu bar is redrawn every minute).
    private static let dateFormatters = Mutex<[String: DateFormatter]>([:])

    /// "08:45:18"
    public static func timeLine(_ d: Date, calendar: Calendar = Fmt.calendar) -> String {
        let style = Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
            locale: locale, timeZone: calendar.timeZone, calendar: calendar)
        return d.formatted(style)
    }
}

extension DateFormatter {
    /// Day names (starting from Sunday), once per language.
    static func weekdays(_ locale: Locale) -> [String] {
        weekdayCache.withLock { cache in
            if let w = cache[locale.identifier] { return w }
            let f = DateFormatter(); f.locale = locale
            let w = f.standaloneWeekdaySymbols ?? []
            cache[locale.identifier] = w
            return w
        }
    }
    private static let weekdayCache = Mutex<[String: [String]]>([:])
}

extension Fmt {
    /// Parses a displayed value ("4,2", "%62", "62%", "+2.1", "1.201") back using the selected language's separators;
    /// nil if there is no number ("restarting").
    public static func number(_ s: String) -> Double? {
        let dec = Character(locale.decimalSeparator ?? ".")
        let kept = s.filter { $0.isNumber || $0 == dec }   // thousands separator, percent sign and signs are dropped
        guard kept.contains(where: \.isNumber) else { return nil }
        return Double(String(kept.map { $0 == dec ? "." : $0 }))
    }
}
