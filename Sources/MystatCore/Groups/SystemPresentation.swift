import Foundation

/// Sistem bölümünün ve panel hücresinin metinleri (§6.3): fan, güç, GPU ve enerji gerçek değerden.
public enum SystemPresentation {
    /// "4.800 dev/dk" | "sessiz" (en düşük devirde) | "duruyor" | "fan yok" (fansız Mac ya da okunamadı).
    public static func fanText(_ s: SystemState) -> String {
        guard s.fanCount > 0 else { return L10n.t("fan.none") }
        if s.fanRPM <= 0 { return L10n.t("fan.stopped") }
        if quiet(s) { return L10n.t("fan.quiet") }
        return L10n.t("unit.rpm", ["rpm": Fmt.int(s.fanRPM)])
    }

    /// "Prizdesin, pil tam dolu." | "Şarj oluyor, pil %80." | "Pildesin, pil %62."
    public static func power(_ s: SystemState, health: Bool = false) -> String {
        if s.onAC, s.battery >= 100 { return L10n.t("power.full") + (health && s.health.hasSuffix(L10n.t("battery.health.good")) ? L10n.t("power.fullHealthy") : ".") }
        let battery = ["battery": Fmt.pct(Double(s.battery))]
        if !s.onAC { return L10n.t("power.onBattery", battery) }
        return L10n.t(s.charging ? "power.charging" : "power.pluggedIn", battery)
    }

    public static func gpuFacts(_ s: SystemState) -> [(String, String)] {
        [(L10n.t("sys.gpu.top"), s.gpuApps.first?.name ?? "—"), (L10n.t("sys.gpu.second"), s.gpuApps.dropFirst().first?.name ?? "—"),
         (L10n.t("sys.gpu.memory"), L10n.t("sys.gpu.shared")), (L10n.t("sys.gpu.displays"), s.displays > 0 ? String(s.displays) : "—")]
    }

    /// GPU kartının durum hapı: kullanım ≥ %70 "Yoğun".
    public static func gpuPill(_ s: SystemState) -> (String, Level) { s.gpuPercent >= 70 ? (L10n.t("sys.gpu.busy"), .warn) : (L10n.t("sys.gpu.calm"), .ok) }

    public static func wattsText(_ g: ProcessGroup) -> String { Fmt.dec1(g.watts) + " W" }

    /// Watt'a göre azalan; toplu macOS satırı ve 0 W gruplar hariç.
    public static func energyTop(_ groups: [ProcessGroup], n: Int) -> [ProcessGroup] {
        Array(groups.filter { $0.id != "sys:macos" && $0.watts > 0 }.sorted { $0.watts > $1.watts }.prefix(n))
    }

    /// En düşük devrin %15 üstüne kadar "sessiz": boştaki ikinci fan (1.471 / en düşük 1.350) her turda gidip gelmesin.
    public static func quiet(_ s: SystemState) -> Bool { s.fanRPM <= max(s.fanMinRPM * 1.15, s.fanMinRPM + 100) }

    public static func heatPill(_ s: SystemState) -> (String, Level) { (s.thermal.thermalWord, s.thermal) }
    public static func slowdown(_ s: SystemState) -> String { L10n.t(s.thermal == .crit ? "sys.slowdown.yes" : s.thermal == .warn ? "sys.slowdown.notYet" : "sys.slowdown.no") }
    public static func heatLabel(_ s: SystemState) -> String { s.fanCount > 0 ? L10n.t("sys.heatLabel.fan", ["fan": fanText(s)]) : L10n.t("sys.heatLabel.fanless") }

    /// §6.3: yüzdenin altında şarj durumu ve (sensör varsa) anlık watt.
    public static func powerLabel(_ s: SystemState, sensors: Bool) -> String {
        let state = L10n.t(s.battery >= 100 && s.onAC ? "sys.power.full" : s.charging ? "sys.power.charging" : "sys.power.battery")
        return sensors && s.watts > 0 ? L10n.t("sys.power.watts", ["state": state, "w": Fmt.int(s.watts)]) : state
    }
}
