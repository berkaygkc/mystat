import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

/// The VM process is split into compose projects, "other containers" and the virtual machine's own overhead.
@Suite(.language("tr")) struct DockerGroupsTests {
    let vm = ProcessGroup(id: "docker:vm", name: "Docker", context: "sanal makine", cpuCores: 3.0, memoryGB: 10, netMBps: 0, uptime: "45 sa",
                          processCount: 1, folder: nil, terminal: nil, port: nil, isOrphan: false, relatedID: nil, isDocker: true,
                          children: [], pids: [900])
    let brave = ProcessGroup(id: "app:/Applications/Brave Browser.app", name: "Brave Browser", context: "14 süreç", cpuCores: 0.4, memoryGB: 2,
                             netMBps: 0, uptime: "3 gün", processCount: 14, folder: nil, terminal: nil, port: nil, isOrphan: false,
                             relatedID: nil, isDocker: false, children: [], pids: [500])

    func c(_ name: String, _ project: String, _ cpu: Double, _ mb: Double) -> Container {
        Container(name: name, image: "img", cpuPercent: cpu, memoryMB: mb, healthy: true, uptime: "2 gün", project: project, dockerID: name)
    }

    @Test func englishContext() {
        L10n.$override.withValue("en") {
            let cs = [c("verifier", "deploy", 62, 1024), c("pg", "deploy", 18, 512), c("tunnel", "initech", 10, 256), c("lane-pg", "", 5, 128)]
            let g = Dictionary(uniqueKeysWithValues: DockerGroups.split([vm, brave], containers: cs).map { ($0.id, $0) })
            #expect(g["docker:project:deploy"]?.context == "deploy · 2 containers"); #expect(g["docker:project:initech"]?.context == "initech · 1 container")
            #expect(g["docker:other"]?.context == "other containers")
        }
    }

    @Test func splitsByProject() {
        let cs = [c("verifier", "deploy", 62, 1024), c("pg", "deploy", 18, 512), c("tunnel", "initech", 10, 256), c("lane-pg", "", 5, 128)]
        let g = Dictionary(uniqueKeysWithValues: DockerGroups.split([vm, brave], containers: cs).map { ($0.id, $0) })
        let deploy = g["docker:project:deploy"]
        #expect(deploy.map { abs($0.cpuCores - 0.8) < 1e-9 && abs($0.memoryGB - 1.5) < 1e-9 } == true)
        #expect(deploy?.name == "Docker" && deploy?.context == "deploy · 2 container" && deploy?.isDocker == true && deploy?.pids == [])
        #expect(deploy?.children.map(\.name) == ["verifier", "pg"] && deploy?.processCount == 2)
        #expect(g["docker:project:initech"]?.context == "initech · 1 container")
        #expect(g["docker:other"]?.context == "diğer container'lar")
        let rest = g["docker:vm"]
        #expect(rest.map { abs($0.cpuCores - 2.05) < 1e-9 && abs($0.memoryGB - 8.125) < 1e-9 } == true)
        #expect(rest?.context == "sanal makine" && rest?.pids == [900])
        #expect(g["app:/Applications/Brave Browser.app"] != nil && g.count == 5)
    }

    @Test func vmOverheadNeverNegative() {
        var small = vm
        small.cpuCores = 0.2
        small.memoryGB = 0.1
        let g = DockerGroups.split([small], containers: [c("a", "p", 50, 512)])
        #expect(g.first { $0.id == "docker:vm" }.map { $0.cpuCores == 0 && $0.memoryGB == 0 } == true)
    }

    @Test func noContainersLeavesGroupsUntouched() {
        #expect(DockerGroups.split([vm, brave], containers: []).map(\.id) == ["docker:vm", "app:/Applications/Brave Browser.app"])
        #expect(DockerGroups.split([brave], containers: [c("a", "p", 50, 512)]).map(\.id) == ["app:/Applications/Brave Browser.app"])
    }
}
