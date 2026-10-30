import Foundation

/// Text and mappings specific to the Monitor window.
public enum MonitorPresentation {
    /// Live value shown in the sidebar.
    public static func navValue(_ section: String, _ s: Snapshot) -> (text: String, level: Level) {
        switch section {
        case "cpu": (Fmt.pct(s.cpu.percent), Thresholds.cpuTotal(s.cpu.percent))
        case "mem": (Fmt.pct(s.memory.percent), s.memory.pressureLevel)
        case "disk": (Fmt.pct(s.disk.percent), Thresholds.diskFree(s.disk.freeGB))
        case "net": ("↓" + Fmt.rate(s.net.downMBps), .ok)
        case "docker": s.capabilities.docker && s.docker.running ? (String(s.docker.containers.count), s.incident?.kind == .docker ? s.incident!.level : .ok) : ("—", .ok)
        case "sys": (s.capabilities.sensors ? Fmt.int(s.system.chipTemp) + "°" : "", s.system.batteryDrain30m != nil ? .warn : s.system.thermal)
        default: ("", .ok)
        }
    }

    /// Incident card in the sidebar: the panel headline, without the trailing period.
    public static func sideIncidentText(_ s: Snapshot) -> String {
        let t = String(GroupPresentation.panelHeadline(s).title.characters)
        return t.hasSuffix(".") ? String(t.dropLast()) : t
    }

    /// One-sentence summary of the incident card.
    public static func incidentSentence(_ s: Snapshot) -> String {
        guard let inc = s.incident else { return "" }
        let dur = L10n.plural("dur.for", inc.minutes)
        switch inc.kind {
        case .cpu:
            let lead = s.groups.first { $0.id == inc.culpritIDs.first }
            guard s.cpu.percent >= 70 else {   // overall load is low, a single group is high
                return L10n.t("monitor.incident.cpu.group", ["name": lead?.name ?? L10n.t("common.aGroup"), "for": dur, "cores": Fmt.dec1(lead?.cpuCores ?? 0)])
            }
            let source = lead.map { $0.folder != nil ? L10n.t("monitor.incident.cpu.fromProject", ["project": $0.context])
                                                     : L10n.t("monitor.incident.cpu.topApp", ["name": $0.name]) } ?? ""
            return L10n.t("monitor.incident.cpu.total", ["for": dur, "pct": Fmt.pct(Double(Int(s.cpu.percent / 10) * 10)), "source": source])
        case .memory:
            let who = s.groups.first { $0.id == inc.culpritIDs.first }?.name
            return L10n.t("monitor.incident.memory", ["for": dur, "pressure": PanelPresentation.pressureWord(inc.level)])
                + (who.map { L10n.t("monitor.incident.memory.grower", ["name": $0]) } ?? "")
        case .disk:
            let lost = GroupPresentation.fact(inc, L10n.t("fact.last24h")).map { L10n.t("monitor.incident.disk.lost", ["amount": $0.trimmingCharacters(in: ["−", "-"])]) } ?? ""
            return L10n.t("monitor.incident.disk", ["free": Fmt.int(s.disk.freeGB), "lost": lost])
        case .docker:
            let who = inc.culpritIDs.first ?? L10n.t("common.aContainer")
            switch GroupPresentation.fact(inc, L10n.t("fact.health")) {
            case L10n.t("docker.health.restarting"): return L10n.t("monitor.incident.docker.restarting", ["who": who, "for": dur])
            case L10n.t("docker.health.unhealthy"): return L10n.t("monitor.incident.docker.unhealthy", ["who": who, "for": dur])
            default: return L10n.t("monitor.incident.docker.cpu", ["who": who, "for": dur, "value": inc.culpritValues.first ?? ""])
            }
        case .heat:
            return s.capabilities.sensors && s.system.fanCount > 0 && s.system.fanRPM > 0
                ? L10n.t("monitor.incident.heat.fans", ["for": dur, "rpm": Fmt.int(s.system.fanRPM)])
                : L10n.t("monitor.incident.heat.state", ["for": dur, "state": s.system.thermal.thermalWord.lowercased(with: Fmt.locale)])
        case .battery:
            let left = GroupPresentation.fact(inc, L10n.t("fact.left")).map { L10n.t("incident.battery.left", ["left": $0]) } ?? ""
            return L10n.t("monitor.incident.battery", ["in": L10n.plural("dur.in", inc.minutes), "drain": Fmt.pct(s.system.batteryDrain30m ?? 0), "left": left])
        }
    }

    /// The section that holds the incident's details.
    public static func section(for kind: IncidentKind) -> String {
        switch kind { case .cpu: "cpu"; case .memory: "mem"; case .disk: "disk"; case .docker: "docker"; case .heat, .battery: "sys" }
    }

    /// Series for the small chart on the incident card.
    public static func seriesKey(for kind: IncidentKind) -> SeriesKey {
        switch kind { case .cpu: .cpu; case .memory: .memPressure; case .disk: .diskWrite; case .docker: .dockerCPU; case .heat: .temp; case .battery: .power }
    }

    public static var sectionTitles: [String: String] {
        Dictionary(uniqueKeysWithValues: ["overview", "cpu", "mem", "disk", "net", "docker", "sys"].map { ($0, L10n.t("section.\($0)")) })
    }

    /// "Investigate in CPU", "Investigate in Memory" … (in Turkish the suffix depends on the section, so it is written by hand in the language file).
    public static func inspectTitle(section: String) -> String {
        ["cpu", "mem", "disk", "net", "docker", "sys"].contains(section) ? L10n.t("inspect.\(section)") : L10n.t("inspect.monitor")
    }
}

extension MonitorPresentation {
    /// Paragraph under the Overview headline.
    public static func overviewLede(_ s: Snapshot) -> String {
        guard let inc = s.incident else {
            let docker = s.capabilities.docker && s.docker.running ? L10n.plural("overview.calm.docker", s.docker.containers.count) : ""
            return L10n.t("overview.calm", ["top": s.calmTop.name, "docker": docker, "free": Fmt.int(s.disk.freeGB)])
        }
        guard inc.kind == .cpu, let lead = s.groups.first(where: { $0.id == inc.culpritIDs.first }) else {
            return GroupPresentation.panelHeadline(s).lede
        }
        // Facts come from the data: the accompanying server only if it is involved in the incident, "normal" only if memory and disk are calm.
        var t = GroupPresentation.cpuLede(lead, s, inc, joined: true)
        if s.memory.pressureLevel == .ok, Thresholds.diskFree(s.disk.freeGB) == .ok { t += L10n.t("overview.normal") }
        return t
    }

    /// Core labels: performance (P) first, then efficiency (E). The live series arrives in this order (`SnapshotBuilder`);
    /// without machine info (sample data) it is 10 + 4.
    public static func coreLabels(count: Int, machine: MachineInfo?) -> (labels: [String], note: String) {
        let p = machine.map { $0.pCores + $0.eCores == count ? $0.pCores : count } ?? Swift.min(10, count)
        let e = count - p
        let labels: [String] = (0..<count).map { (i: Int) -> String in
            i < p ? L10n.t("cpu.core.p", ["n": "\(i + 1)"]) : L10n.t("cpu.core.e", ["n": "\(i - p + 1)"])
        }
        let note: String = e > 0 ? L10n.t("cpu.cores.split", ["p": "\(p)", "e": "\(e)"]) : L10n.t("cpu.cores.count", ["n": "\(p)"])
        return (labels, note)
    }

    public static var cpuCalmLede: String { L10n.t("cpu.calmLede") }
}
