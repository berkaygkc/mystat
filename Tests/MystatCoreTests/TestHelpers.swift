import Foundation

extension Calendar {
    /// A Gregorian calendar with a fixed time zone (Europe/Istanbul) for tests.
    static var trTest: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return cal
    }
}

@testable import MystatCore

extension StatusBlockModel {
    /// Sample block model in the calm state.
    static var sample: StatusBlockModel {
        StatusBlockModel(alert: nil,
                         metrics: [StatusMetric(label: "CPU", value: "%14", level: .ok),
                                   StatusMetric(label: "RAM", value: "%78", level: .ok),
                                   StatusMetric(label: "DİSK", value: "%62", level: .ok)],
                         down: "↓2,4", up: "↑0,3", date: "28 Eki 2026 Çar", time: "08:45:18")
    }
}
