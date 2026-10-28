import Foundation

/// Bellek, Ağ, Docker ve Sistem bölümlerinin başlık ve açıklama cümleleri (mockup `secMem`, `secNet`, `secDocker`, `secSys`).
public enum SectionText {
    public struct Head: Sendable {
        public let title: String
        public let soft: String
        public let lede: String
        public let level: Level
    }

    public static func memory(_ s: Snapshot) -> Head {
        let m = s.memory
        let soft = m.pressureLevel == .ok ? "ama baskı düşük." : "ve baskı \(PanelPresentation.pressureWord(m.pressureLevel))."
        // Örnek veride sıkıştırma oranı ~2,08; Faz 2'de gerçek sıkıştırma öncesi boyut gelir.
        let original = Fmt.int(m.compressed * 2.08)
        let swap = m.swapGB > 0 ? "Swap \(Fmt.dec1(m.swapGB)) GB'a çıktı; makine zorlanıyor." : "Swap yok, yani makine sıkışmış değil."
        return Head(title: "\(Fmt.pct(m.percent)) dolu,", soft: soft,
                    lede: "\(Fmt.int(m.totalGB)) GB'ın \(Fmt.dec1(m.usedGB)) GB'ı kullanımda. macOS diske yazmak yerine belleği sıkıştırıyor: \(original) GB'lık veriyi \(Fmt.dec1(m.compressed)) GB'a sığdırmış. \(swap)",
                    level: m.pressureLevel)
    }

    public static func networkLede(_ s: Snapshot) -> String {
        let top = GroupPresentation.sorted(s.groups, by: .network).first?.name ?? ""
        return "\(s.net.iface) · \(s.net.ssid) ağı. Bugün \(Fmt.dec1(s.net.todayDownGB)) GB indirildi, \(Fmt.dec1(s.net.todayUpGB)) GB gönderildi. Şu an en çok \(top) indiriyor."
    }

    public static func docker(_ s: Snapshot) -> Head {
        let d = s.docker
        let cpu = d.containers.reduce(0) { $0 + $1.cpuPercent }
        let mem = d.containers.reduce(0) { $0 + $1.memoryMB } / 1024
        let n = d.containers.count
        let disk = "Docker'ın diski \(Fmt.int(d.disk.rawGB)) GB"
        let reclaim = "\(Fmt.dec1(d.disk.volumesReclaimGB)) GB'ı geri kazanılabilir."
        let level: Level = s.incident?.kind == .docker ? s.incident!.level : .ok
        if let top = d.containers.max(by: { $0.cpuPercent < $1.cpuPercent }), top.cpuPercent >= 30 {
            return Head(title: "\(n) container ayakta.", soft: "Biri yoğun çalışıyor.",
                        lede: "\(top.name) tek başına \(Fmt.pct(top.cpuPercent)) CPU kullanıyor; container'ların toplamı \(Fmt.pct(cpu)). \(disk), \(reclaim)",
                        level: level)
        }
        return Head(title: "\(n) container ayakta,", soft: "hepsi sakin.",
                    lede: "Container'lar toplam \(Fmt.pct(cpu)) CPU ve \(Fmt.dec1(mem)) GB bellek kullanıyor. \(disk); \(reclaim)",
                    level: level)
    }

    public static func system(_ s: Snapshot) -> (title: AttributedString, lede: String, level: Level) {
        let sys = s.system
        func emph(_ before: String, _ e: String) -> AttributedString {
            var a = AttributedString(e); a.inlinePresentationIntent = .emphasized
            return AttributedString(before) + a
        }
        if let drain = sys.batteryDrain30m {
            return (emph("Pil hızlı eriyor: ", "30 dk'da \(Fmt.pct(drain))"),
                    "Prizde değilsin; pil %\(sys.battery). Bu hızla 1 sa 10 dk yeter.", .warn)
        }
        if sys.thermal != .ok {
            return (emph("Çip ısınıyor: ", "\(Fmt.int(sys.chipTemp))°"),
                    "Fanlar \(Fmt.int(sys.fanRPM)) dev/dk ile dönüyor. macOS henüz yavaşlatmaya başlamadı; yük sürerse başlayabilir. Prizdesin, pil tam dolu.",
                    sys.thermal)
        }
        return (AttributedString("Serin ve sessiz."),
                "Çip \(Fmt.int(sys.chipTemp))°, fanlar duruyor. Prizdesin, pil tam dolu ve sağlığı iyi.", .ok)
    }
}
