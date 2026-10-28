import Foundation

/// §8/3: Mac tarafında tüm container'lar tek sanal makine süreci olarak görünür; değerleri Engine API'den bölünür.
/// Her compose projesi bir satır ("Docker · deploy · 13 container"), projesizler "diğer container'lar", sanal makinenin
/// kendi ek yükü (VM eksi container toplamı, sıfırın altına inmez) "sanal makine" satırı. VM'in pid'leri ek yük satırında
/// kalır: disk yazımı ve grup geçmişi `docker:vm` kimliğiyle sürer.
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
                                    context: project.isEmpty ? "diğer container'lar" : "\(project) · \(cs.count) container",
                                    cpuCores: cs.reduce(0) { $0 + $1.cpuPercent } / 100, memoryGB: cs.reduce(0) { $0 + $1.memoryMB } / 1024,
                                    netMBps: 0, uptime: vm.uptime, processCount: cs.count, folder: nil, terminal: nil, port: nil,
                                    isOrphan: false, relatedID: nil, isDocker: true,
                                    children: cs.map { ChildProcess(name: $0.name, cpuCores: $0.cpuPercent / 100) }))
        }
        return out.sorted { $0.cpuCores != $1.cpuCores ? $0.cpuCores > $1.cpuCores : $0.memoryGB > $1.memoryGB }
    }
}
