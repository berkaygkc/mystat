import Foundation
import Testing
@testable import MystatCore

/// Kenar menüsünün alt satırı ve pil olguları gerçek veriden (spec §6.1, §6.3 Sistem).
@MainActor @Suite struct MachineInfoTests {
    let now = Date(timeIntervalSince1970: 1_793_166_318)

    @Test func footerFormat() {
        let m = MachineInfo(model: "MacBook Pro", chip: "M4 Pro", pCores: 10, eCores: 4, memoryGB: 48, boot: now.addingTimeInterval(-3 * 86_400))
        #expect(m.footer(now: now) == "MacBook Pro · M4 Pro\n14 çekirdek · 48 GB · açık 3 gün")
        let fresh = MachineInfo(model: "Mac mini", chip: "M4", pCores: 4, eCores: 6, memoryGB: 16, boot: now.addingTimeInterval(-5 * 3600))
        #expect(fresh.footer(now: now) == "Mac mini · M4\n10 çekirdek · 16 GB · açık 5 sa")
    }

    @Test func sampleFooterIsUnchanged() {
        #expect(SampleSource(seed: 1).snapshot.system.machine?.footer(now: Date()) == "MacBook Pro · M4 Pro\n14 çekirdek · 48 GB · açık 3 gün")
    }

    @Test func batteryFacts() {
        let b = BatteryReading(percent: 100, charging: false, onAC: true, adapterWatts: 140, adapterUSBC: true,
                               cycles: 75, designCapacity: 8579, maxCapacity: 7819)
        #expect(b.adapterText == "140 W USB-C")
        #expect(b.healthText == "%91 · iyi")
        #expect(b.capacityText == "7.819 / 8.579 mAh")
        let none = BatteryReading(percent: 50, charging: false, onAC: false, adapterWatts: nil, adapterUSBC: false,
                                  cycles: nil, designCapacity: nil, maxCapacity: nil)
        #expect(none.adapterText == "—" && none.healthText == "—" && none.capacityText == "—")
    }

    /// Prize takılı değilken "Prizdesin" denmez (Task 2 kararı burada kesinleşir).
    @Test func onBatteryWithoutSensors() {
        var s = SampleSource(seed: 1).snapshot
        s.capabilities = SourceCapabilities(docker: false, sensors: false, diskScan: false, netDetails: false)
        s.system.onAC = false; s.system.charging = false; s.system.battery = 64
        #expect(SectionText.system(s).lede == "Termal durum normal. Pildesin, pil %64.")
    }
}
