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
    public static func pressureWord(_ l: Level) -> String { l == .crit ? "yüksek" : l == .warn ? "orta" : "düşük" }

    public static func cells(_ s: Snapshot) -> [PanelCell] {
        let inc = s.incident
        let cpuLevel = Thresholds.cpuTotal(s.cpu.percent)
        let cpuSub: String
        if let inc, inc.kind == .cpu {   // toplam düşükse olay tek grubun yükü: yüzde iddiası yazılmaz
            cpuSub = s.cpu.percent >= 70 ? "\(inc.minutes) dakikadır %\(Int(s.cpu.percent / 10) * 10) üzerinde" : "\(inc.minutes) dakikadır yoğun"
        } else { cpuSub = "\(s.cpu.cores.count) çekirdek, sakin" }
        let dockerCores = s.docker.containers.reduce(0) { $0 + $1.cpuPercent } / 100
        let sysSub: String
        if let drain = s.system.batteryDrain30m, drain > 0 { sysSub = "Pil %\(s.system.battery), prizde değil" }
        else if s.system.thermal != .ok { sysSub = "Fan \(Fmt.int(s.system.fanRPM)) dev/dk, ısınıyor" }
        else { sysSub = "Fan sessiz, pil %\(s.system.battery)" }
        let sysLevel: Level = s.system.batteryDrain30m != nil ? .warn : s.system.thermal
        let caps = s.capabilities
        return [
            PanelCell(section: "cpu", label: "İşlemci", big: Fmt.pct(s.cpu.percent), unit: nil, sub: cpuSub, level: cpuLevel),
            PanelCell(section: "mem", label: "Bellek", big: Fmt.pct(s.memory.percent), unit: nil,
                      sub: "\(Fmt.dec1(s.memory.usedGB)) / \(Fmt.int(s.memory.totalGB)) GB, baskı \(pressureWord(s.memory.pressureLevel))",
                      level: s.memory.pressureLevel),
            PanelCell(section: "disk", label: "Disk", big: Fmt.pct(s.disk.percent), unit: nil, sub: "\(Fmt.int(s.disk.freeGB)) GB boş",
                      level: Thresholds.diskFree(s.disk.freeGB)),
            PanelCell(section: "net", label: "Ağ", big: Fmt.rate(s.net.downMBps), unit: "MB/s",
                      sub: "↑ \(Fmt.rate(s.net.upMBps)) MB/s · \(s.net.iface)", level: .ok),
            caps.docker && !s.docker.running
                ? PanelCell(section: "docker", label: "Docker", big: "—", unit: nil, sub: "çalışmıyor", level: .ok)
                : caps.docker
                ? PanelCell(section: "docker", label: "Docker", big: String(s.docker.containers.count), unit: nil,
                            sub: "container · \(Fmt.cores(dockerCores)) çekirdek", level: inc?.kind == .docker ? inc!.level : .ok)
                : PanelCell(section: "docker", label: "Docker", big: "—", unit: nil, sub: "bağlanmadı", level: .ok),
            caps.sensors
                ? PanelCell(section: "sys", label: "Sistem", big: Fmt.int(s.system.chipTemp) + "°", unit: nil, sub: sysSub, level: sysLevel)
                : PanelCell(section: "sys", label: "Sistem", big: s.system.thermal.thermalWord, unit: nil, sub: "pil %\(s.system.battery)", level: sysLevel),
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
