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
        let soft = m.pressureLevel == .ok ? L10n.t("section.mem.soft.ok") : L10n.t("section.mem.soft", ["pressure": PanelPresentation.pressureWord(m.pressureLevel)])
        // Örnek veride sıkıştırma oranı ~2,08; Faz 2'de gerçek sıkıştırma öncesi boyut gelir.
        let original = Fmt.int(m.compressed * 2.08)
        let swap = m.swapGB > 0 ? L10n.t("section.mem.swap", ["gb": Fmt.dec1(m.swapGB)]) : L10n.t("section.mem.noSwap")
        return Head(title: L10n.t("section.mem.title", ["pct": Fmt.pct(m.percent)]), soft: soft,
                    lede: L10n.t("section.mem.lede", ["total": Fmt.int(m.totalGB), "used": Fmt.dec1(m.usedGB), "original": original,
                                                     "compressed": Fmt.dec1(m.compressed), "swap": swap]),
                    level: m.pressureLevel)
    }

    public static func networkLede(_ s: Snapshot) -> String {
        let today = L10n.t("section.net.today", ["down": Fmt.dec1(s.net.todayDownGB), "up": Fmt.dec1(s.net.todayUpGB)])
        guard s.capabilities.netDetails else {   // Wi‑Fi adı ve uygulama bazında ağ 2e'de
            return L10n.t("section.net.name.iface", ["iface": s.net.iface]) + today
        }
        let name = s.net.ssid.isEmpty ? L10n.t("section.net.name.iface", ["iface": s.net.iface])
                                      : L10n.t("section.net.name.ssid", ["iface": s.net.iface, "ssid": s.net.ssid])
        let top = GroupPresentation.sorted(s.groups, by: .network).first.flatMap { $0.netMBps >= 0.05 ? $0.name : nil }
        return name + today + (top.map { L10n.t("section.net.top", ["name": $0]) } ?? "")
    }

    public static func docker(_ s: Snapshot) -> Head {
        guard s.capabilities.docker else {
            return Head(title: L10n.t("section.docker.notConnected.title"), soft: "", lede: L10n.t("section.docker.notConnected.lede"), level: .ok)
        }
        let d = s.docker
        guard d.running else {   // Docker Desktop kapalı ya da yok (§9.1): sakin durum
            return Head(title: L10n.t("section.docker.notRunning.title"), soft: "", lede: L10n.t("section.docker.notRunning.lede"), level: .ok)
        }
        let cpu = d.containers.reduce(0) { $0 + $1.cpuPercent }
        let mem = d.containers.reduce(0) { $0 + $1.memoryMB } / 1024
        let n = d.containers.count
        let disk = d.disk.rawGB.map { L10n.t("section.docker.disk.raw", ["gb": Fmt.int($0)]) } ?? L10n.t("section.docker.disk.data", ["gb": Fmt.dec1(d.disk.dataGB)])
        let reclaim = L10n.t("section.docker.reclaim", ["gb": Fmt.dec1(d.disk.volumesReclaimGB)])
        let level: Level = s.incident?.kind == .docker ? s.incident!.level : .ok
        if let top = d.containers.max(by: { $0.cpuPercent < $1.cpuPercent }), top.cpuPercent >= 30 {
            return Head(title: L10n.plural("section.docker.busy.title", n), soft: L10n.t("section.docker.busy.soft"),
                        lede: L10n.t("section.docker.busy.lede", ["name": top.name, "pct": Fmt.pct(top.cpuPercent), "total": Fmt.pct(cpu),
                                                                 "disk": disk, "reclaim": reclaim]),
                        level: level)
        }
        return Head(title: L10n.plural("section.docker.calm.title", n), soft: L10n.t("section.docker.calm.soft"),
                    lede: L10n.t("section.docker.calm.lede", ["cpu": Fmt.pct(cpu), "mem": Fmt.dec1(mem), "disk": disk, "reclaim": reclaim]),
                    level: level)
    }

    /// `home`: tarama ağacının kökü; tarama yoksa (ya da ağaç bellekte değilse) nil veya çocuksuz.
    public static func disk(_ s: Snapshot, home: DiskNode?, freedGB: Double) -> Head {
        let title = L10n.t("section.disk.title", ["pct": Fmt.pct(s.disk.percent)]), soft = L10n.t("section.disk.soft", ["free": Fmt.int(s.disk.freeGB)])
        guard s.capabilities.diskScan, let home, let kids = home.children else {   // harita kalemleri tarama ister
            let p = s.disk.purgeableGB
            return Head(title: title, soft: soft, lede: p >= 1 ? L10n.t("section.disk.purgeable", ["gb": Fmt.int(p)]) : "",
                        level: Thresholds.diskFree(s.disk.freeGB))
        }
        var lede: String
        if freedGB > 0 {
            lede = L10n.t("section.disk.freed", ["freed": Fmt.size(freedGB), "home": Fmt.size(home.size)])
        } else {
            lede = L10n.t("section.disk.home", ["home": Fmt.size(home.size)])
            if let top = kids.filter({ $0.kind != .other }).max(by: { $0.size < $1.size }) {
                lede = L10n.t("section.disk.homeTop", ["home": Fmt.size(home.size), "name": top.name])
                let docker = s.docker.disk.rawGB ?? s.docker.disk.dataGB
                if top.name == "Library", s.capabilities.docker, docker >= 1 { lede += L10n.t("section.disk.dockerInLibrary", ["gb": Fmt.int(docker)]) }
                lede += "."
            }
            if let w = s.disk.topWriter { lede += L10n.t("section.disk.writer", ["name": w]) }
        }
        return Head(title: title, soft: soft, lede: lede, level: Thresholds.diskFree(s.disk.freeGB))
    }

    public static func system(_ s: Snapshot) -> (title: AttributedString, lede: String, level: Level) {
        let sys = s.system, battery = Fmt.pct(Double(sys.battery))
        if let drain = sys.batteryDrain30m {
            let left = s.incident.flatMap { GroupPresentation.fact($0, L10n.t("fact.left")) }.map { L10n.t("section.sys.battery.left", ["left": $0]) } ?? ""
            return (L10n.emphasized("section.sys.battery.title", emph: L10n.t("headline.battery.emph", ["drain": Fmt.pct(drain)])),
                    L10n.t("section.sys.battery.lede", ["battery": battery, "left": left]), .warn)
        }
        if !s.capabilities.sensors {   // sıcaklık ve fan 2c'de; termal durum ve pil
            let power = L10n.t(!sys.onAC ? "power.onBattery" : sys.charging && sys.battery < 100 ? "power.charging" : "power.pluggedIn", ["battery": battery])
            switch sys.thermal {
            case .ok: return (AttributedString(L10n.t("section.sys.cool.title")), L10n.t("section.sys.thermal.ok") + power, .ok)
            case .warn: return (AttributedString(L10n.t("section.sys.warming.title")), L10n.t("section.sys.thermal.warn") + power, .warn)
            case .crit: return (AttributedString(L10n.t("section.sys.hot.title")), L10n.t("section.sys.throttling") + power, .crit)
            }
        }
        let fan = SystemPresentation.fanText(sys)
        if sys.thermal != .ok {
            let fans = sys.fanCount > 0 && sys.fanRPM > 0 ? L10n.t("headline.heat.fans", ["rpm": Fmt.int(sys.fanRPM)]) : ""
            let slowing = L10n.t(sys.thermal == .crit ? "section.sys.throttling" : "section.sys.notThrottling")
            return (L10n.emphasized("section.sys.heat.title", emph: "\(Fmt.int(sys.chipTemp))°"), fans + slowing + SystemPresentation.power(sys), sys.thermal)
        }
        let fans = sys.fanCount > 0 ? L10n.t("section.sys.cool.fans", ["fan": fan]) : ""
        return (AttributedString(L10n.t("section.sys.cool.title")),
                L10n.t("section.sys.cool.lede", ["temp": Fmt.int(sys.chipTemp), "fans": fans]) + SystemPresentation.power(sys, health: true), .ok)
    }
}
