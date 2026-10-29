import Foundation

public struct PanelCell: Sendable, Equatable {
    public let section: String   // MonitorSection ham değeri: overview, cpu, mem, disk, net, docker, sys
    public let label: String
    public let big: String
    public let unit: String?
    public let sub: String
    public let level: Level
}

public struct CulpritRow: Sendable, Equatable {
    public let name: String
    public let context: String
    public let value: String
    public let unit: String
    /// Tıklanınca seçilecek süreç grubu (container ise "docker").
    public let groupID: String
}

/// Panel ve Genel Bakış'taki 2×3 özet hücreleri ile olay sorumluları.
public enum PanelPresentation {
    public static func pressureWord(_ l: Level) -> String { L10n.t(l == .crit ? "pressure.crit" : l == .warn ? "pressure.warn" : "pressure.ok") }

    public static func cells(_ s: Snapshot) -> [PanelCell] {
        let inc = s.incident
        let cpuLevel = Thresholds.cpuTotal(s.cpu.percent)
        let cpuSub: String
        if let inc, inc.kind == .cpu {   // toplam düşükse olay tek grubun yükü: yüzde iddiası yazılmaz
            let dur = L10n.plural("dur.forShort", inc.minutes)   // hücre dar: kısa süre
            cpuSub = s.cpu.percent >= 70 ? L10n.t("panel.cpu.above", ["for": dur, "pct": Fmt.pct(Double(Int(s.cpu.percent / 10) * 10))])
                                         : L10n.t("panel.cpu.busy", ["for": dur])
        } else { cpuSub = L10n.t("panel.cpu.calm", ["n": String(s.cpu.cores.count)]) }
        let dockerCores = s.docker.containers.reduce(0) { $0 + $1.cpuPercent } / 100
        let sysSub: String, battery = Fmt.pct(Double(s.system.battery)), rpm = Fmt.int(s.system.fanRPM)
        if let drain = s.system.batteryDrain30m, drain > 0 { sysSub = L10n.t("panel.sys.unplugged", ["battery": battery]) }
        else if s.system.thermal != .ok {
            sysSub = s.system.fanCount > 0 && s.system.fanRPM > 0 ? L10n.t("panel.sys.fanWarming", ["rpm": rpm]) : L10n.t("panel.sys.warming", ["battery": battery])
        } else if s.system.fanCount == 0 {
            sysSub = L10n.t("panel.sys.battery", ["battery": battery])
        } else {   // panelde "duruyor" da "sessiz" (Faz 1 metni)
            let quiet = SystemPresentation.quiet(s.system)
            sysSub = L10n.t("panel.sys.fan", ["fan": quiet ? L10n.t("fan.quiet") : L10n.t("unit.rpm", ["rpm": rpm]), "battery": battery])
        }
        let sysLevel: Level = s.system.batteryDrain30m != nil ? .warn : s.system.thermal
        let caps = s.capabilities
        return [
            PanelCell(section: "cpu", label: L10n.t("section.cpu"), big: Fmt.pct(s.cpu.percent), unit: nil, sub: cpuSub, level: cpuLevel),
            PanelCell(section: "mem", label: L10n.t("section.mem"), big: Fmt.pct(s.memory.percent), unit: nil,
                      sub: L10n.t("panel.mem.sub", ["used": Fmt.dec1(s.memory.usedGB), "total": Fmt.int(s.memory.totalGB),
                                                    "pressure": L10n.t(s.memory.pressureLevel == .crit ? "panel.mem.pressure.crit"
                                                                       : s.memory.pressureLevel == .warn ? "panel.mem.pressure.warn" : "panel.mem.pressure.ok")]),
                      level: s.memory.pressureLevel),
            PanelCell(section: "disk", label: L10n.t("section.disk"), big: Fmt.pct(s.disk.percent), unit: nil,
                      sub: L10n.t("panel.disk.sub", ["free": Fmt.int(s.disk.freeGB)]), level: Thresholds.diskFree(s.disk.freeGB)),
            PanelCell(section: "net", label: L10n.t("section.net"), big: Fmt.rate(s.net.downMBps), unit: "MB/s",
                      sub: "↑ \(Fmt.rate(s.net.upMBps)) MB/s · \(s.net.iface)", level: .ok),
            caps.docker && !s.docker.running
                ? PanelCell(section: "docker", label: L10n.t("section.docker"), big: "—", unit: nil, sub: L10n.t("panel.docker.notRunning"), level: .ok)
                : caps.docker
                ? PanelCell(section: "docker", label: L10n.t("section.docker"), big: String(s.docker.containers.count), unit: nil,
                            sub: L10n.t("panel.docker.sub", ["cores": Fmt.cores(dockerCores)]), level: inc?.kind == .docker ? inc!.level : .ok)
                : PanelCell(section: "docker", label: L10n.t("section.docker"), big: "—", unit: nil, sub: L10n.t("panel.docker.notConnected"), level: .ok),
            caps.sensors
                ? PanelCell(section: "sys", label: L10n.t("section.sys"), big: Fmt.int(s.system.chipTemp) + "°", unit: nil, sub: sysSub, level: sysLevel)
                : PanelCell(section: "sys", label: L10n.t("section.sys"), big: s.system.thermal.thermalWord, unit: nil,
                            sub: L10n.t("panel.sys.noSensors", ["battery": battery]), level: sysLevel),
        ]
    }

    public static func culprits(_ s: Snapshot) -> [CulpritRow] {
        guard let inc = s.incident else { return [] }
        return zip(inc.culpritIDs, inc.culpritValues).map { id, value in
            if let g = s.groups.first(where: { $0.id == id }) {
                return CulpritRow(name: g.name, context: g.context, value: value, unit: inc.culpritUnit, groupID: g.id)
            }
            let project = s.docker.containers.first { $0.name == id }?.project ?? ""
            return CulpritRow(name: id, context: project, value: value, unit: inc.culpritUnit, groupID: "docker")
        }
    }
}
