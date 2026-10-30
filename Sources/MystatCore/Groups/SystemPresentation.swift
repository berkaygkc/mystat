import Foundation

/// Texts for the System section and panel cell: fan, power, GPU and energy from real values.
public enum SystemPresentation {
    /// "4,800 rpm" | "quiet" (at minimum speed) | "stopped" | "no fan" (fanless Mac or unreadable).
    public static func fanText(_ s: SystemState) -> String {
        guard s.fanCount > 0 else { return L10n.t("fan.none") }
        if s.fanRPM <= 0 { return L10n.t("fan.stopped") }
        if quiet(s) { return L10n.t("fan.quiet") }
        return L10n.t("unit.rpm", ["rpm": Fmt.int(s.fanRPM)])
    }

    /// "You're on power, battery full." | "Charging, battery 80%." | "On battery, 62%."
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

    /// Status pill of the GPU card: usage ≥ 70% shows "Busy".
    public static func gpuPill(_ s: SystemState) -> (String, Level) { s.gpuPercent >= 70 ? (L10n.t("sys.gpu.busy"), .warn) : (L10n.t("sys.gpu.calm"), .ok) }

    public static func wattsText(_ g: ProcessGroup) -> String { Fmt.dec1(g.watts) + " W" }

    /// Descending by watts; excludes the aggregate macOS row and 0 W groups.
    public static func energyTop(_ groups: [ProcessGroup], n: Int) -> [ProcessGroup] {
        Array(groups.filter { $0.id != "sys:macos" && $0.watts > 0 }.sorted { $0.watts > $1.watts }.prefix(n))
    }

    /// "Quiet" up to 15% above the minimum speed: an idle second fan (1,471 / minimum 1,350) should not flip back and forth every round.
    public static func quiet(_ s: SystemState) -> Bool { s.fanRPM <= max(s.fanMinRPM * 1.15, s.fanMinRPM + 100) }

    public static func heatPill(_ s: SystemState) -> (String, Level) { (s.thermal.thermalWord, s.thermal) }
    public static func slowdown(_ s: SystemState) -> String { L10n.t(s.thermal == .crit ? "sys.slowdown.yes" : s.thermal == .warn ? "sys.slowdown.notYet" : "sys.slowdown.no") }
    public static func heatLabel(_ s: SystemState) -> String { s.fanCount > 0 ? L10n.t("sys.heatLabel.fan", ["fan": fanText(s)]) : L10n.t("sys.heatLabel.fanless") }

    /// Below the percentage: charging state and (if a sensor exists) the instantaneous watts.
    public static func powerLabel(_ s: SystemState, sensors: Bool) -> String {
        let state = L10n.t(s.battery >= 100 && s.onAC ? "sys.power.full" : s.charging ? "sys.power.charging" : "sys.power.battery")
        return sensors && s.watts > 0 ? L10n.t("sys.power.watts", ["state": state, "w": Fmt.int(s.watts)]) : state
    }
}
