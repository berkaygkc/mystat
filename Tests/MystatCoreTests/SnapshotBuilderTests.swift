import Foundation
import Testing
@testable import MystatCore

/// Ölçümler → Snapshot (spec §5 sakin başlık, §7.3 öneriler).
@MainActor @Suite struct SnapshotBuilderTests {
    let now = Date(timeIntervalSince1970: 1_793_166_318)

    func group(_ id: String, _ name: String, ctx: String, cores: Double, orphan: Bool = false, uptime: String = "14 dk") -> ProcessGroup {
        ProcessGroup(id: id, name: name, context: ctx, cpuCores: cores, memoryGB: 1, netMBps: 0, uptime: uptime, processCount: 2,
                     folder: nil, terminal: nil, port: nil, isOrphan: orphan, relatedID: nil, isDocker: false, children: [])
    }

    func measurements() -> LiveMeasurements {
        let base = SampleSource(seed: 1).snapshot
        return LiveMeasurements(cpu: base.cpu, memory: base.memory, disk: base.disk,
                                net: (down: 2.4, up: 0.3, todayDown: 12.4, todayUp: 1.8), iface: "en0", ip: "192.168.1.122",
                                groups: [group("app:/Applications/Brave Browser.app", "Brave Browser", ctx: "24 süreç", cores: 1.12),
                                         group("dev:/p/web:3011", "Next.js dev", ctx: "acmecorp/web · :3011", cores: 0.1, orphan: true)],
                                thermal: .ok, battery: BatteryReading(percent: 100, charging: false, onAC: true, adapterWatts: 65, adapterUSBC: true,
                                                                      cycles: 75, designCapacity: 8579, maxCapacity: 7787),
                                batteryDrain30m: nil, machine: MachineInfo(model: "MacBook Pro", chip: "M4 Pro", pCores: 10, eCores: 4, memoryGB: 48, boot: now),
                                downloads: [(name: "Xcode_26.2.xip", gb: 9.5, idleDays: 21)], coreCount: 14)
    }

    @Test func calmTopIsBusiestGroupAsPercentOfMachine() {
        let s = SnapshotBuilder.build(measurements(), incident: nil, capabilities: .all)
        #expect(s.calmTop.name == "Brave Browser" && s.calmTop.percent == 8)                     // 1,12 / 14
        #expect(GroupPresentation.panelHeadline(s).lede == "Makine rahat. En yoğun uygulama Brave Browser, %8 ile.")
    }

    @Test func suggestionsFromOrphanAndDownloads() {
        let sg = SnapshotBuilder.build(measurements(), incident: nil, capabilities: .all).suggestions
        #expect(sg.map(\.title) == ["acmecorp/web :3011 sahipsiz çalışıyor", "İndirilenler'de 9,5 GB'lık Xcode_26.2.xip"])
        #expect(sg.map(\.detail) == ["Başlatan terminal kapanmış · 14 dk", "3 haftadır açılmamış"])
        #expect(sg[0].target == .group("dev:/p/web:3011") && sg[1].target == .disk(["Downloads"]))
    }

    @Test func netAndSystemFields() {
        let s = SnapshotBuilder.build(measurements(), incident: nil, capabilities: .all)
        #expect(s.net.iface == "en0" && s.net.details.map(\.label) == ["Arayüz", "Yerel IP"] && s.net.details[1].value == "192.168.1.122")
        #expect(s.system.battery == 100 && s.system.onAC && s.system.adapter == "65 W USB-C" && s.system.health == "%91 · iyi")
        #expect(s.system.machine?.chip == "M4 Pro")
        #expect(s.capabilities == .all)
    }
    /// Sistem süreçlerinin toplu satırı bir uygulama değil; sakin başlıkta en yoğun gerçek grup söylenir.
    @Test func calmTopSkipsResidualSystemRow() {
        var m = measurements()
        m.groups.insert(group("sys:macos", "macOS", ctx: "sistem süreçleri", cores: 3.5), at: 0)
        #expect(SnapshotBuilder.build(m, incident: nil, capabilities: .all).calmTop.name == "Brave Browser")
    }
}
