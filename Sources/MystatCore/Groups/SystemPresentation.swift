import Foundation

/// Sistem bölümünün ve panel hücresinin metinleri (§6.3): fan, güç, GPU ve enerji gerçek değerden.
public enum SystemPresentation {
    /// "4.800 dev/dk" | "sessiz" (en düşük devirde) | "duruyor" | "fan yok" (fansız Mac ya da okunamadı).
    public static func fanText(_ s: SystemState) -> String {
        guard s.fanCount > 0 else { return "fan yok" }
        if s.fanRPM <= 0 { return "duruyor" }
        if s.fanRPM <= s.fanMinRPM + 100 { return "sessiz" }
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
}
