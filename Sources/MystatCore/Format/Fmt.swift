import Foundation
import Synchronization

/// Seçili dilin biçimleri (sayı, yüzde, tarih, süre). Mockup'taki `pc`, `f1`, `f0`, `gb`, `fsz` karşılıkları.
public enum Fmt {
    /// Seçili dilin `Locale`'i (`_meta.locale`).
    public static var locale: Locale { L10n.current.locale }

    /// Saat ve tarih her zaman Gregoryen (bölge ayarı Budist ya da İslami takvim olsa da).
    public static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = locale
        c.timeZone = .current
        return c
    }

    /// Gerçek veride NaN/inf gelebilir; çökmeden "—".
    static let missing = "—"

    /// "%14" / "14%" (`_meta.percent`), tamsayıya yuvarlanır.
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

    /// Çekirdek değeri; sıfırdan büyük ama 0,05'ten küçükse "<0,1".
    public static func cores(_ v: Double) -> String { v > 0 && v < 0.05 ? "<" + dec1(0.1) : dec1(v) }

    /// Bellek: ≥10 GB tamsayı, aksi tek ondalık.
    public static func mem(_ gb: Double) -> String { (gb >= 10 ? int(gb) : dec1(gb)) + " GB" }

    /// Disk boyutu (ondalık birimler): GB → MB → KB.
    public static func size(_ gb: Double) -> String {
        guard gb.isFinite else { return missing }
        if gb >= 10 { return int(gb) + " GB" }
        if gb >= 1 { return dec1(gb) + " GB" }
        let mb = gb * 1000
        if mb >= 10 { return int(mb) + " MB" }
        if mb >= 1 { return dec1(mb) + " MB" }
        return int(max(1, gb * 1_000_000)) + " KB"
    }

    /// Açık kalma süresi: "14 dk", "2 sa 14 dk", "45 sa", "3 gün".
    public static func uptime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return missing }
        let m = Int(seconds / 60), h = m / 60
        if h < 1 { return L10n.t("unit.minutes", ["m": String(max(1, m))]) }
        if h < 10 { return m % 60 == 0 ? L10n.t("unit.hours", ["h": String(h)]) : L10n.t("unit.hoursMinutes", ["h": String(h), "m": String(m % 60)]) }
        if h < 72 { return L10n.t("unit.hours", ["h": String(h)]) }
        return L10n.plural("unit.days", h / 24)
    }

    /// Ağ hızı sayısı ("2,4"); birim ayrı yazılır.
    public static func rate(_ mbps: Double) -> String { dec1(mbps) }

    /// "28 Ekim 2026 Çarşamba" / "Thursday, October 29, 2026" (`_meta.dateLine`).
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

    /// Dil, kalıp, takvim ve saat dilimi başına bir biçimleyici (menü çubuğu her dakika çizilir).
    private static let dateFormatters = Mutex<[String: DateFormatter]>([:])

    /// "08:45:18"
    public static func timeLine(_ d: Date, calendar: Calendar = Fmt.calendar) -> String {
        let style = Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
            locale: locale, timeZone: calendar.timeZone, calendar: calendar)
        return d.formatted(style)
    }
}
