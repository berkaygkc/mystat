import CoreGraphics
import Foundation

public struct StatusMetric: Equatable, Sendable {
    public var label: String
    public var value: String
    public var level: Level
    public init(label: String, value: String, level: Level) { self.label = label; self.value = value; self.level = level }
}

/// Menü çubuğu bloğunun içeriği. Değişmediyse yeniden çizilmez.
public struct StatusBlockModel: Equatable, Sendable {
    public var alert: StatusMetric?
    public var metrics: [StatusMetric]
    public var down: String
    public var up: String
    public var date: String
    public var time: String
    public init(alert: StatusMetric?, metrics: [StatusMetric], down: String, up: String, date: String, time: String) {
        self.alert = alert; self.metrics = metrics; self.down = down; self.up = up; self.date = date; self.time = time
    }
}

/// Bloğun ölçüleri (mockup menubar.html → `.blk`, `.m`).
public enum StatusBlockLayout {
    public static let blockPadding: CGFloat = 5
    public static let gap: CGFloat = 1
    public static let metricPadding: CGFloat = 3
    public static let clockGap: CGFloat = 5
    public static let labelSize: CGFloat = 8.5, valueSize: CGFloat = 12, netSize: CGFloat = 10.5
    public static let dateSize: CGFloat = 10, timeSize: CGFloat = 12.5

    /// Genişliğin değerle oynamaması için ayrılan en geniş örnek metinler (Review Focus #1).
    /// CPU en oynak değer: %100'e kadar yer ayrılır. RAM ve DİSK nadiren üç haneye çıkar; sıkılık için iki hane.
    public static let cpuTemplate = "%100", valueTemplate = "%88", alertTemplate = "−%88", netTemplate = "↓88,8"
    public static let dateTemplate = "28 Ağustos 2026 Cumartesi", timeTemplate = "88:88:88"

    public enum Part: Equatable { case alert, metric(Int), net, clock }

    public static func model(_ s: Snapshot, now: Date, calendar: Calendar) -> StatusBlockModel {
        let metrics = [
            StatusMetric(label: "CPU", value: Fmt.pct(s.cpu.percent), level: Thresholds.cpuTotal(s.cpu.percent)),
            StatusMetric(label: "RAM", value: Fmt.pct(s.memory.percent), level: s.memory.pressureLevel),
            StatusMetric(label: "DİSK", value: Fmt.pct(s.disk.percent), level: Thresholds.diskFree(s.disk.freeGB)),
        ]
        return StatusBlockModel(alert: alert(s), metrics: metrics,
                                down: "↓" + Fmt.rate(s.net.downMBps), up: "↑" + Fmt.rate(s.net.upMBps),
                                date: Fmt.dateLine(now, calendar: calendar), time: Fmt.timeLine(now, calendar: calendar))
    }

    /// Isı, Pil ve Docker'ın kalıcı öğesi yok; olay anında bloğun içinde belirir (spec §4).
    static func alert(_ s: Snapshot) -> StatusMetric? {
        if s.system.thermal != .ok { return StatusMetric(label: "ISI", value: Fmt.int(s.system.chipTemp) + "°", level: s.system.thermal) }
        if let drain = s.system.batteryDrain30m { return StatusMetric(label: "PİL", value: "−" + Fmt.pct(drain), level: .warn) }
        if let inc = s.incident, inc.kind == .docker { return StatusMetric(label: "DOCKER", value: inc.culpritValues.first ?? "", level: inc.level) }
        return nil
    }

    /// Her parçanın genişliği, soldan sağa. `measure(metin, punto, kalın)`.
    public static func parts(_ m: StatusBlockModel, measure: (String, CGFloat, Bool) -> CGFloat) -> [(Part, CGFloat)] {
        func metric(_ x: StatusMetric, template: String) -> CGFloat {
            max(measure(x.label, labelSize, true), measure(x.value, valueSize, true), measure(template, valueSize, true)) + metricPadding * 2
        }
        var out: [(Part, CGFloat)] = []
        if let a = m.alert { out.append((.alert, metric(a, template: alertTemplate))) }
        for (i, x) in m.metrics.enumerated() { out.append((.metric(i), metric(x, template: i == 0 ? cpuTemplate : valueTemplate))) }
        out.append((.net, max(measure(m.down, netSize, true), measure(m.up, netSize, true), measure(netTemplate, netSize, true)) + metricPadding * 2))
        out.append((.clock, max(measure(m.date, dateSize, false), measure(dateTemplate, dateSize, false),
                                measure(m.time, timeSize, true), measure(timeTemplate, timeSize, true)) + metricPadding * 2))
        return out
    }

    public static func width(_ m: StatusBlockModel, measure: (String, CGFloat, Bool) -> CGFloat) -> CGFloat {
        let p = parts(m, measure: measure)
        return blockPadding * 2 + p.reduce(0) { $0 + $1.1 } + gap * CGFloat(p.count - 1) + clockGap
    }
}
