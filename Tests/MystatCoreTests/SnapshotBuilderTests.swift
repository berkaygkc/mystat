import Foundation
import MystatTestSupport
import Testing
@testable import MystatCore

/// Measurements → Snapshot (the calm headline and the suggestions).
@MainActor @Suite(.language("tr")) struct SnapshotBuilderTests {
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
        #expect(s.calmTop.name == "Brave Browser" && s.calmTop.percent == 8)                     // 1.12 / 14
        #expect(GroupPresentation.panelHeadline(s).lede == "Makine rahat. En yoğun uygulama Brave Browser, %8 ile.")
    }

    @Test func englishSuggestions() {
        L10n.$override.withValue("en") {
            let sg = SnapshotBuilder.build(measurements(), incident: nil, capabilities: .all).suggestions
            #expect(sg.map(\.title) == ["acmecorp/web :3011 is running orphaned", "9.5 GB Xcode_26.2.xip in Downloads"])
        }
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
    /// The aggregate row of system processes is not an app; the calm headline names the busiest real group.
    @Test func calmTopSkipsResidualSystemRow() {
        var m = measurements()
        m.groups.insert(group("sys:macos", "macOS", ctx: "sistem süreçleri", cores: 3.5), at: 0)
        #expect(SnapshotBuilder.build(m, incident: nil, capabilities: .all).calmTop.name == "Brave Browser")
    }

    /// A slow drain on battery is not a warning: the drain is carried over only while a battery incident exists (the menu bar stays calm).
    @Test func batteryDrainOnlyDuringBatteryIncident() {
        let m0 = measurements()
        let m = LiveMeasurements(cpu: m0.cpu, memory: m0.memory, disk: m0.disk, net: m0.net, iface: m0.iface, ip: m0.ip, groups: m0.groups,
                                 thermal: .ok, battery: BatteryReading(percent: 80, charging: false, onAC: false, adapterWatts: 0, adapterUSBC: false,
                                                                       cycles: 75, designCapacity: 8579, maxCapacity: 7787),
                                 batteryDrain30m: 3, machine: m0.machine, downloads: [], coreCount: 14)
        let calm = SnapshotBuilder.build(m, incident: nil, capabilities: .all)
        #expect(calm.system.batteryDrain30m == nil && !calm.system.onAC)
        #expect(StatusBlockLayout.alert(calm) == nil)
        let inc = Incident(kind: .battery, level: .warn, startedAt: "10:00", minutes: 3, peakPercent: 25, culpritIDs: [], culpritValues: [],
                           culpritUnit: "çekirdek", facts: [])
        #expect(SnapshotBuilder.build(m, incident: inc, capabilities: .all).system.batteryDrain30m == 3)
    }

    /// Logical CPUs 0–3 are efficiency cores and 4–13 are performance cores (ioreg cluster-type); the UI shows performance first.
    @Test func coresArePerformanceFirst() {
        let m0 = measurements()
        var cpu = m0.cpu
        cpu.cores = (0..<14).map(Double.init)
        let m = LiveMeasurements(cpu: cpu, memory: m0.memory, disk: m0.disk, net: m0.net, iface: m0.iface, ip: m0.ip, groups: m0.groups,
                                 thermal: .ok, battery: nil, batteryDrain30m: nil, machine: m0.machine, downloads: [], coreCount: 14)
        let s = SnapshotBuilder.build(m, incident: nil, capabilities: .all)
        let order: [Double] = [4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 0, 1, 2, 3]
        #expect(s.cpu.cores == order)
        let labels: [String] = ["P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9", "P10", "V1", "V2", "V3", "V4"]
        #expect(MonitorPresentation.coreLabels(count: 14, machine: m0.machine).labels == labels)
        #expect(MonitorPresentation.coreLabels(count: 14, machine: m0.machine).note == "10 performans · 4 verimlilik")
        let m4 = MachineInfo(model: "MacBook Air", chip: "M2", pCores: 4, eCores: 4, memoryGB: 16, boot: now)
        #expect(MonitorPresentation.coreLabels(count: 8, machine: m4).labels == ["P1", "P2", "P3", "P4", "V1", "V2", "V3", "V4"])
    }

    /// The Docker suggestion counts the amount that is safe given the user's volume choice: unnamed volumes + images (not named data volumes).
    @Test func dockerSuggestionUsesSafeReclaim() {
        func with(_ anon: Double, _ images: Double, running: Bool = true) -> [Suggestion] {
            var m = measurements()
            m.docker = DockerState(running: running, containers: [], vmMemoryGB: 15.6, vmCores: 14,
                                   disk: DockerDisk(imagesGB: 8.764, imagesReclaimGB: images, imagesCount: 21, volumesGB: 17.41, volumesReclaimGB: 12.63,
                                                    volumesCount: 192, buildCacheGB: 0, rawGB: nil, imagesUnusedCount: 4, volumesUnusedCount: 177,
                                                    volumesAnonReclaimGB: anon, volumesAnonUnusedCount: 116))
            return SnapshotBuilder.build(m, incident: nil, capabilities: .all).suggestions.filter { $0.target == .docker }
        }
        let s = with(7.05, 2.77)
        #expect(s.map(\.title) == ["Docker'da 9,8 GB geri kazanılabilir"] && s.first?.detail == "116 adsız volume · 4 image")
        #expect(with(2, 2).isEmpty)
        #expect(with(7.05, 2.77, running: false).isEmpty)
    }

    @Test func netStateFromLink() {
        var m = measurements()
        let link = NetLink(bsdName: "en0", displayName: "Wi‑Fi", localIP: "192.168.1.42", router: "192.168.1.1", dns: ["1.1.1.1"],
                           wifi: WiFiReading(ssid: nil, rssi: -60, noise: -90, txRateMbps: 195, channel: 100, bandGHz: 5), linkMbps: nil)
        m.link = link; m.latencyMs = nil; m.perAppAvailable = false; m.ssidAccess = .needsPermission; m.perAppReady = false
        let n = SnapshotBuilder.build(m, incident: nil, capabilities: .all).net
        #expect(n.iface == "Wi‑Fi"); #expect(n.ssid == "")
        #expect(n.details == NetPresentation.facts(link))
        #expect(n.latencyMs.isNaN); #expect(n.ssidAccess == .needsPermission); #expect(n.perAppAvailable == false); #expect(n.perAppReady == false)
        m.link?.wifi?.ssid = "Ev"; m.latencyMs = 4
        let k = SnapshotBuilder.build(m, incident: nil, capabilities: .all).net
        #expect(k.ssid == "Ev"); #expect(k.ssidAccess == .known); #expect(k.latencyMs == 4)
        m.link = nil
        let h = SnapshotBuilder.build(m, incident: nil, capabilities: .all).net   // Network section off: basic info only
        #expect(h.iface == "en0"); #expect(h.details.map(\.label) == ["Arayüz", "Yerel IP"])
    }
}
