import MystatCore

/// Birden çok görünümde kullanılan arayüz metinleri.
public enum UIText {
    /// Bölüm başlığının üstündeki küçük büyük harfli satır ("İŞLEMCİ", "AĞ" …); Genel Bakış'ta "ŞU AN".
    public static func sectionKicker(_ s: MonitorSection) -> String {
        s == .overview ? L10n.t("headline.kicker") : L10n.t("kicker.\(s.rawValue)")
    }

    public static var quit: String { L10n.t("panel.quit") }
}
