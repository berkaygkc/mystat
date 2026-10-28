import Foundation

/// Sistem bölümünün ve panel hücresinin metinleri (§6.3): fan, güç, GPU ve enerji gerçek değerden.
public enum SystemPresentation {
    /// "4.800 dev/dk" | "sessiz" (en düşük devirde) | "duruyor" | "fan yok" (fansız Mac ya da okunamadı).
    public static func fanText(_ s: SystemState) -> String {
        guard s.fanCount > 0 else { return "fan yok" }
        if s.fanRPM <= 0 { return "duruyor" }
        if quiet(s) { return "sessiz" }
        return "\(Fmt.int(s.fanRPM)) dev/dk"
    }

    /// "Prizdesin, pil tam dolu." | "Şarj oluyor, pil %80." | "Pildesin, pil %62."
    public static func power(_ s: SystemState, health: Bool = false) -> String {
        if s.onAC, s.battery >= 100 { return "Prizdesin, pil tam dolu" + (health && s.health.hasSuffix("iyi") ? " ve sağlığı iyi." : ".") }
        if !s.onAC { return "Pildesin, pil %\(s.battery)." }
        return s.charging ? "Şarj oluyor, pil %\(s.battery)." : "Prizdesin, pil %\(s.battery)."
    }

    public static func gpuFacts(_ s: SystemState) -> [(String, String)] {
        [("En çok kullanan", s.gpuApps.first?.name ?? "—"), ("İkinci", s.gpuApps.dropFirst().first?.name ?? "—"),
         ("Bellek", "Paylaşımlı"), ("Ekranlar", s.displays > 0 ? String(s.displays) : "—")]
    }

    /// GPU kartının durum hapı: kullanım ≥ %70 "Yoğun".
    public static func gpuPill(_ s: SystemState) -> (String, Level) { s.gpuPercent >= 70 ? ("Yoğun", .warn) : ("Sakin", .ok) }

    public static func wattsText(_ g: ProcessGroup) -> String { Fmt.dec1(g.watts) + " W" }

    /// Watt'a göre azalan; toplu macOS satırı ve 0 W gruplar hariç.
    public static func energyTop(_ groups: [ProcessGroup], n: Int) -> [ProcessGroup] {
        Array(groups.filter { $0.id != "sys:macos" && $0.watts > 0 }.sorted { $0.watts > $1.watts }.prefix(n))
    }

    /// En düşük devrin %15 üstüne kadar "sessiz": boştaki ikinci fan (1.471 / en düşük 1.350) her turda gidip gelmesin.
    public static func quiet(_ s: SystemState) -> Bool { s.fanRPM <= max(s.fanMinRPM * 1.15, s.fanMinRPM + 100) }

    public static func heatPill(_ s: SystemState) -> (String, Level) { (s.thermal.thermalWord, s.thermal) }
    public static func slowdown(_ s: SystemState) -> String { s.thermal == .crit ? "Var" : s.thermal == .warn ? "Henüz yok" : "Yok" }
    public static func heatLabel(_ s: SystemState) -> String { "Çip ortalaması · " + (s.fanCount > 0 ? "fan " + fanText(s) : "fansız") }

    /// §6.3: yüzdenin altında şarj durumu ve (sensör varsa) anlık watt.
    public static func powerLabel(_ s: SystemState, sensors: Bool) -> String {
        let state = s.battery >= 100 && s.onAC ? "Tam dolu" : s.charging ? "Şarj oluyor" : "Pil"
        return sensors && s.watts > 0 ? state + " · şu an \(Fmt.int(s.watts)) W harcanıyor" : state
    }
}
