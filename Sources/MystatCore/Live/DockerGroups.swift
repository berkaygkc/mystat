import Foundation

/// On the Mac all containers appear as a single virtual machine process; their values are split out using the Engine API.
/// Each compose project becomes one row ("Docker · deploy · 13 containers"), containers without a project become "other containers", and the virtual machine's
/// own overhead (VM minus the container total, never below zero) becomes the "virtual machine" row. The VM's pids stay in the overhead row:
/// disk writes and group history continue under the `docker:vm` id.
public enum DockerGroups {
    public static func split(_ groups: [ProcessGroup], containers: [Container]) -> [ProcessGroup] {
        guard !containers.isEmpty, let i = groups.firstIndex(where: { $0.id == "docker:vm" }) else { return groups }
        let vm = groups[i]
        var out = groups
        var rest = vm
        rest.cpuCores = max(0, vm.cpuCores - containers.reduce(0) { $0 + $1.cpuPercent } / 100)
        rest.memoryGB = max(0, vm.memoryGB - containers.reduce(0) { $0 + $1.memoryMB } / 1024)
        out[i] = rest
        let byProject = Dictionary(grouping: containers, by: \.project)
        for project in byProject.keys.sorted() {
            let cs = byProject[project]!
            out.append(ProcessGroup(id: project.isEmpty ? "docker:other" : "docker:project:\(project)", name: "Docker",
                                    context: project.isEmpty ? L10n.t("docker.project.other") : L10n.plural("group.docker", cs.count, ["project": project]),
                                    cpuCores: cs.reduce(0) { $0 + $1.cpuPercent } / 100, memoryGB: cs.reduce(0) { $0 + $1.memoryMB } / 1024,
                                    netMBps: 0, uptime: vm.uptime, processCount: cs.count, folder: nil, terminal: nil, port: nil,
                                    isOrphan: false, relatedID: nil, isDocker: true,
                                    children: cs.map { ChildProcess(name: $0.name, cpuCores: $0.cpuPercent / 100) }))
        }
        return out.sorted { $0.cpuCores != $1.cpuCores ? $0.cpuCores > $1.cpuCores : $0.memoryGB > $1.memoryGB }
    }
}
