import Foundation
import Testing
@testable import MystatCore

/// SMC değer çözümü ve keşfedilen anahtarların sınıflanması (önek kuralı).
@Suite struct SensorMapTests {
    @Test func decodesSMCTypes() {
        #expect(SMCValue.decode(type: "flt ", bytes: [0x9A, 0x99, 0xA9, 0x44]).map { abs($0 - 1356.8) < 0.01 } == true)
        #expect(SMCValue.decode(type: "ui8 ", bytes: [2]) == 2)
        #expect(SMCValue.decode(type: "ui16", bytes: [0x01, 0x02]) == 258)
        #expect(SMCValue.decode(type: "fpe2", bytes: [0x15, 0x40]) == 1360)
        #expect(SMCValue.decode(type: "sp78", bytes: [0x1D, 0x80]) == 29.5)
        #expect(SMCValue.decode(type: "ch8*", bytes: [0x41]) == nil)
        #expect(SMCValue.decode(type: "flt ", bytes: [0x01]) == nil)            // eksik bayt
    }

    @Test func classifyKeepsPlausibleTemps() {
        let m = SensorMap.classify(["Tp1i": 54.9, "Tp01": 3.4, "Te04": 55.4, "Tg05": 60.8, "TB0T": 29.4, "TPD0": 53, "TCMz": 80.7], fans: 2)
        #expect(m.cpu == ["Te04", "Tp1i"] && m.gpu == ["Tg05"] && m.battery == "TB0T" && m.fans == 2)
    }

    @Test func sampleIsEvenAndDeterministic() {
        let m = SensorMap(cpu: (0..<40).map { String(format: "Tp%02d", $0) }, gpu: [], battery: nil, fans: 0)
        let s = m.sample(m.cpu, max: 8)
        #expect(s.count == 8 && s.first == "Tp00" && s.last == "Tp39" && s == m.sample(m.cpu, max: 8))
        #expect(m.sample(["Tp1", "Tp2"], max: 8) == ["Tp1", "Tp2"])
    }
}
