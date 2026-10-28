import Foundation

/// tr-TR biçimlendirme yardımcıları. Mockup'taki `pc`, `f1`, `f0`, `gb`, `fsz` karşılıkları.
public enum Fmt {
    static let tr = Locale(identifier: "tr_TR")

    /// "%14" — yüzde işareti başta, tamsayıya yuvarlanır.
    public static func pct(_ v: Double) -> String { "%" + String(Int(v.rounded())) }

    /// "4,2"
    public static func dec1(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(1)).locale(tr))
    }

    /// "4.800"
    public static func int(_ v: Double) -> String { Int(v.rounded()).formatted(.number.locale(tr)) }

    /// Çekirdek değeri; sıfırdan büyük ama 0,05'ten küçükse "<0,1".
    public static func cores(_ v: Double) -> String { v > 0 && v < 0.05 ? "<0,1" : dec1(v) }

    /// Bellek: ≥10 GB tamsayı, aksi tek ondalık.
    public static func mem(_ gb: Double) -> String { (gb >= 10 ? int(gb) : dec1(gb)) + " GB" }

    /// Disk boyutu (ondalık birimler): GB → MB → KB.
    public static func size(_ gb: Double) -> String {
        if gb >= 10 { return int(gb) + " GB" }
        if gb >= 1 { return dec1(gb) + " GB" }
        let mb = gb * 1000
        if mb >= 10 { return int(mb) + " MB" }
        if mb >= 1 { return dec1(mb) + " MB" }
        return int(max(1, gb * 1_000_000)) + " KB"
    }

    /// Ağ hızı sayısı ("2,4"); birim ayrı yazılır.
    public static func rate(_ mbps: Double) -> String { dec1(mbps) }

    /// "28 Ekim 2026 Çarşamba"
    public static func dateLine(_ d: Date, calendar: Calendar = .current) -> String {
        let style = Date.VerbatimFormatStyle(
            format: "\(day: .defaultDigits) \(month: .wide) \(year: .defaultDigits) \(weekday: .wide)",
            locale: tr, timeZone: calendar.timeZone, calendar: calendar)
        return d.formatted(style)
    }

    /// "08:45:18"
    public static func timeLine(_ d: Date, calendar: Calendar = .current) -> String {
        let style = Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
            locale: tr, timeZone: calendar.timeZone, calendar: calendar)
        return d.formatted(style)
    }
}
