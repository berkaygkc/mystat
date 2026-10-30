import Foundation

/// Texts for the Docker section: action confirmations and notifications.
public enum DockerPresentation {
    public static func confirm(_ a: DockerAction, disk d: DockerDisk) -> (title: String, message: String, confirm: String, destructive: Bool) {
        switch a {
        case .pruneAnonymousVolumes:
            return (L10n.t("docker.confirm.pruneAnon.title"),
                    L10n.plural("docker.confirm.pruneAnon.message", d.volumesAnonUnusedCount, ["gb": Fmt.dec1(d.volumesAnonReclaimGB)]),
                    L10n.t("docker.confirm.clean"), false)
        case .pruneNamedVolumes:
            let n = max(0, d.volumesUnusedCount - d.volumesAnonUnusedCount), gb = max(0, d.volumesReclaimGB - d.volumesAnonReclaimGB)
            return (L10n.t("docker.confirm.pruneNamed.title"), L10n.plural("docker.confirm.pruneNamed.message", n, ["gb": Fmt.dec1(gb)]),
                    L10n.t("docker.confirm.pruneNamed.button"), true)
        case .pruneImages:
            return (L10n.t("docker.confirm.pruneImages.title"),
                    L10n.plural("docker.confirm.pruneImages.message", d.imagesUnusedCount, ["gb": Fmt.dec1(d.imagesReclaimGB)]),
                    L10n.t("docker.confirm.clean"), false)
        case .restart(_, let name):
            return (L10n.t("docker.confirm.restart.title", ["name": name]), L10n.t("docker.confirm.restart.message"), L10n.t("docker.confirm.restart.button"), false)
        case .stop(_, let name):
            return (L10n.t("docker.confirm.stop.title", ["name": name]), L10n.t("docker.confirm.stop.message"), L10n.t("docker.confirm.stop.button"), true)
        }
    }

    /// Interim notification shown right after confirmation.
    public static func progress(_ a: DockerAction) -> String {
        switch a { case .restart: L10n.t("docker.progress.restart"); case .stop: L10n.t("docker.progress.stop"); default: L10n.t("docker.progress.clean") }
    }

    public static func toast(_ a: DockerAction, _ o: DockerActionOutcome) -> String {
        switch (a, o) {
        case (_, .failed(let message)): message
        case (.restart(_, let name), .done): L10n.t("docker.toast.restarted", ["name": name])
        case (.stop(_, let name), .done): L10n.t("docker.toast.stopped", ["name": name])
        case (_, .done(let gb)): (gb ?? 0) >= 0.05 ? L10n.t("docker.toast.cleaned", ["gb": Fmt.dec1(gb ?? 0)]) : L10n.t("docker.toast.nothing")
        }
    }
}

/// A compose project in the container table (containers without a project are "other containers").
public struct DockerProjectRow: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    /// Descending by CPU.
    public let containers: [Container]
    public let cpuPercent: Double, memoryGB: Double
    /// "15 containers · all running" | "3 containers · 1 with problems".
    public let summary: String
    /// A container is restarting or unhealthy.
    public let troubled: Bool
}

extension DockerPresentation {
    /// Projects with problems first, then by CPU.
    public static func projects(_ d: DockerState) -> [DockerProjectRow] {
        Dictionary(grouping: d.containers, by: \.project).map { project, cs in
            let bad = cs.filter { $0.restarting || !$0.healthy }.count
            return DockerProjectRow(name: project.isEmpty ? L10n.t("docker.project.other") : project,
                                    containers: cs.sorted { $0.cpuPercent > $1.cpuPercent },
                                    cpuPercent: cs.reduce(0) { $0 + $1.cpuPercent }, memoryGB: cs.reduce(0) { $0 + $1.memoryMB } / 1024,
                                    summary: bad == 0 ? L10n.plural("docker.project.ok", cs.count) : L10n.plural("docker.project.bad", cs.count, ["bad": String(bad)]),
                                    troubled: bad > 0)
        }
        .sorted { $0.troubled != $1.troubled ? $0.troubled : $0.cpuPercent != $1.cpuPercent ? $0.cpuPercent > $1.cpuPercent : $0.name < $1.name }
    }

    /// "27 GB · last 30 days +9 GB": the virtual disk file (or Docker's data if it cannot be read) and the trend, if any.
    public static func diskNote(_ d: DockerState) -> String {
        let size = "\(Fmt.int(d.disk.rawGB ?? d.disk.dataGB)) GB"
        guard let t = d.trend30GB else { return size }
        return L10n.t("docker.diskNote.trend", ["size": size, "trend": (t < 0 ? "−" : "+") + Fmt.int(abs(t)) + " GB"])
    }
}
