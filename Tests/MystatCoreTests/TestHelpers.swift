import Foundation

extension Calendar {
    /// Testlerde sabit saat dilimli (Europe/Istanbul) Gregoryen takvim.
    static var trTest: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return cal
    }
}

@testable import MystatCore

extension StatusBlockModel {
    /// Sakin durumda örnek blok modeli.
    static var sample: StatusBlockModel {
        StatusBlockModel(alert: nil,
                         metrics: [StatusMetric(label: "CPU", value: "%14", level: .ok),
                                   StatusMetric(label: "RAM", value: "%78", level: .ok),
                                   StatusMetric(label: "DİSK", value: "%62", level: .ok)],
                         down: "↓2,4", up: "↑0,3", date: "28 Ekim 2026 Çarşamba", time: "08:45:18")
    }
}
