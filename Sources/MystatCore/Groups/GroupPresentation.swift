import Foundation

public enum GroupMetric: Hashable, Sendable { case cpu, memory, network }

/// Group lists, headline sentences, and the "Copy Diagnosis" text.
public enum GroupPresentation {
    public static func value(_ g: ProcessGroup, _ m: GroupMetric) -> Double {
        switch m { case .cpu: g.cpuCores; case .memory: g.memoryGB; case .network: g.netMBps }
    }

    public static func sorted(_ groups: [ProcessGroup], by m: GroupMetric) -> [ProcessGroup] {
        groups.sorted { value($0, m) > value($1, m) }
    }

    /// "Who's using it" (Network): largest first, at most 12. Real data has dozens of groups; past 12, those with no traffic
    /// are dropped (when idle the list is empty). Sample data with few groups is shown in full.
    public static func networkUsers(_ groups: [ProcessGroup]) -> [ProcessGroup] {
        Array(sorted(groups.count > 12 ? groups.filter { $0.netMBps > 0 } : groups, by: .network).prefix(12))
    }

    public static func related(of g: ProcessGroup, in all: [ProcessGroup]) -> ProcessGroup? {
        g.relatedID.flatMap { id in all.first { $0.id == id } }
    }

    /// Diagnosis copied to the clipboard. No grammatical suffix follows the time, because Turkish suffix harmony depends on how the digits are pronounced.
    public static func diagnosis(_ g: ProcessGroup, incident: Incident?) -> String {
        var lines = [L10n.t("diag.using", ["name": g.name, "context": g.context.isEmpty ? "" : " (\(g.context))",
                                           "cores": Fmt.cores(g.cpuCores), "mem": Fmt.mem(g.memoryGB)])]
        if let inc = incident, inc.kind == .cpu, g.cpuCores > 1 {
            lines.append(L10n.plural("diag.high", inc.minutes, ["start": inc.startedAt, "peak": Fmt.pct(inc.peakPercent)]))
        }
        lines.append(L10n.t("diag.uptime", ["uptime": g.uptime, "count": String(g.processCount)]))
        if let f = g.folder { lines.append(L10n.t("diag.folder", ["folder": f])) }
        if let p = g.port { lines.append(L10n.t("diag.port", ["port": String(p)])) }
        if !g.children.isEmpty {
            let top = g.children.prefix(3).map { "\($0.name) \(Fmt.cores($0.cpuCores))" }.joined(separator: ", ")
            lines.append(L10n.t("diag.children", ["list": top]))
        }
        if g.isOrphan { lines.append(L10n.t("diag.orphan")) }
        return lines.joined(separator: "\n")
    }

    /// Headline for the panel and Overview. The emphasized part is marked with `.emphasized`; the UI colors it red/orange.
    public static func panelHeadline(_ s: Snapshot) -> (kicker: String, title: AttributedString, lede: String) {
        guard let inc = s.incident else {
            return (L10n.t("headline.kicker"), AttributedString(L10n.t("headline.calm.title")),
                    L10n.t("headline.calm.lede", ["top": s.calmTop.name, "pct": Fmt.pct(Double(s.calmTop.percent))]))
        }
        let kicker = L10n.plural("headline.kicker.incident", inc.minutes)
        let name = { (id: String) in s.groups.first { $0.id == id }?.name ?? id }
        switch inc.kind {
        case .cpu:
            let lead = s.groups.first { $0.id == inc.culpritIDs.first }
            return (kicker, title("headline.cpu.title", emph: lead?.name ?? ""), lead.map { cpuLede($0, s, inc) } ?? "")
        case .memory:
            let grew = zip(inc.culpritIDs, inc.culpritValues).prefix(2).map { L10n.t("headline.memory.item", ["name": name($0), "gb": String($1.dropFirst())]) }
            let swap = L10n.t("headline.memory.swap", ["gb": Fmt.dec1(s.memory.swapGB)])
            guard let top = inc.culpritIDs.first else { return (kicker, AttributedString(L10n.t("headline.memory.title")), swap) }   // no growing group
            return (kicker, title("headline.memory.titleTop", emph: name(top)),
                    L10n.plural("headline.memory.lede", inc.minutes, ["list": grew.joined(separator: ", ")]) + swap)
        case .disk:
            var parts: [String] = []
            if let lost = fact(inc, L10n.t("fact.last24h")) { parts.append(L10n.t("headline.disk.lost", ["amount": lost.trimmingCharacters(in: ["−", "-"])])) }
            var writer = inc.culpritIDs.first.map { [L10n.t("headline.disk.writer", ["name": name($0)])] } ?? []
            if s.capabilities.docker, s.docker.running, s.docker.disk.volumesReclaimGB >= 0.05 {
                writer.append(L10n.t("headline.disk.dockerReclaim", ["gb": Fmt.dec1(s.docker.disk.volumesReclaimGB)]))
            }
            if !writer.isEmpty { parts.append(writer.joined(separator: "; ") + ".") }
            return (kicker, title("headline.disk.title", emph: "\(Fmt.int(s.disk.freeGB)) GB"), parts.joined(separator: " "))
        case .docker:
            let who = inc.culpritIDs.first ?? L10n.t("common.aContainer")
            let project = fact(inc, L10n.t("fact.project")).flatMap { $0 == "—" ? nil : $0 }
            let lede = { (key: String, args: [String: String]) in
                project.map { L10n.t(key + "Project", args.merging(["project": $0]) { a, _ in a }) } ?? L10n.t(key, args)
            }
            switch fact(inc, L10n.t("fact.health")) {
            case L10n.t("docker.health.restarting"):
                return (kicker, title("headline.docker.restarting.title", emph: who), lede("headline.docker.restarting.lede", [:]))
            case L10n.t("docker.health.unhealthy"):
                return (kicker, title("headline.docker.unhealthy.title", emph: who), lede("headline.docker.unhealthy.lede", [:]))
            default:
                let othersCalm = !s.docker.containers.contains { $0.name != who && $0.cpuPercent >= 30 }
                return (kicker, title("headline.docker.busy.title", emph: who, ["for": L10n.plural("dur.for", inc.minutes)]),
                        lede("headline.docker.busy.lede", ["value": inc.culpritValues.first ?? ""]) + (othersCalm ? L10n.t("headline.docker.othersCalm") : ""))
            }
        case .heat:
            let fans = s.capabilities.sensors && s.system.fanCount > 0 && s.system.fanRPM > 0 ? L10n.t("headline.heat.fans", ["rpm": Fmt.int(s.system.fanRPM)]) : ""
            let slow = L10n.t(s.system.thermal == .crit ? "headline.heat.throttling" : "headline.heat.notThrottling")
            let head = s.capabilities.sensors ? title("headline.heat.title", emph: "\(Fmt.int(s.system.chipTemp))°")
                                              : title("headline.heat.titleNoSensors", emph: L10n.t("headline.heat.titleNoSensors.emph"))
            return (kicker, head, fans + slow)
        case .battery:
            let drain = Fmt.pct(s.system.batteryDrain30m ?? 0)
            let left = fact(inc, L10n.t("fact.left")).map { L10n.t("incident.battery.left", ["left": $0]) } ?? ""
            let who = inc.culpritIDs.first.map { L10n.t("headline.battery.who", ["name": name($0)]) } ?? ""
            return (kicker, title("headline.battery.title", emph: L10n.t("headline.battery.emph", ["drain": drain])),
                    L10n.t("headline.battery.lede", ["left": left, "who": who]))
        }
    }

    /// The named fact of an incident (in sample data e.g. "Last 24 h", "Remaining"; in live data only what can be measured).
    static func fact(_ inc: Incident, _ label: String) -> String? { inc.facts.first { $0.label == label }?.value }

    /// CPU incident description: the project for a group with a project, otherwise the group's name; plus an accompanying sentence if a second culprit is in the same project.
    /// `joined`: the accompanying sentence is attached to the main sentence with a semicolon (Overview).
    static func cpuLede(_ lead: ProcessGroup, _ s: Snapshot, _ inc: Incident, joined: Bool = false) -> String {
        let cores = Fmt.dec1(lead.cpuCores)
        let out = lead.folder != nil ? L10n.t("cpu.lede.project", ["project": lead.context, "cores": cores])
                                     : L10n.t("cpu.lede.group", ["name": lead.name, "cores": cores])
        if inc.culpritIDs.count > 1, let second = s.groups.first(where: { $0.id == inc.culpritIDs[1] }),
           second.relatedID == lead.id || lead.relatedID == second.id {
            let server = second.name.hasPrefix("Next.js") ? "Next.js" : second.name
            return out + (joined ? L10n.t("cpu.lede.companionJoined", ["server": server]) : "." + L10n.t("cpu.lede.companion", ["server": server]))
        }
        return out + "."
    }

    /// Child process rows in the group detail: the top 5 by CPU; the rest as "+ N more small processes".
    public static func childRows(_ g: ProcessGroup) -> (rows: [ChildProcess], more: Int) {
        let rows = Array(g.children.sorted { $0.cpuCores > $1.cpuCores }.prefix(5))
        return (rows, max(0, g.processCount - rows.count))
    }

    /// CPU section headline: ("91%", " · 12.7 of 14 cores busy") or ("CPU is relaxed.", "14%").
    public static func cpuHeadline(_ s: Snapshot) -> (title: String, soft: String) {
        let pct = Fmt.pct(s.cpu.percent)
        guard s.cpu.percent >= 70 else { return (L10n.t("cpu.headline.calm"), pct) }
        let total = s.cpu.cores.count
        let used = Fmt.dec1(s.cpu.percent / 100 * Double(total))
        return (pct, L10n.t("cpu.headline.soft", ["total": String(total), "used": used]))
    }

    private static func title(_ key: String, emph: String, _ args: [String: String] = [:]) -> AttributedString {
        L10n.emphasized(key, emph: emph, args)
    }
}
