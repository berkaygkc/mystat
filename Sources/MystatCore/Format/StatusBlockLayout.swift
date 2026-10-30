import CoreGraphics
import Foundation

public struct StatusMetric: Equatable, Sendable {
    public var label: String
    public var value: String
    public var level: Level
    public init(label: String, value: String, level: Level) { self.label = label; self.value = value; self.level = level }
}

/// Content of the menu bar block. Not redrawn if unchanged.
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

/// Dimensions of the block.
public enum StatusBlockLayout {
    public static let blockPadding: CGFloat = 5
    public static let gap: CGFloat = 1
    public static let metricPadding: CGFloat = 3
    public static let clockGap: CGFloat = 2
    public static let labelSize: CGFloat = 8.5, valueSize: CGFloat = 12, netSize: CGFloat = 10.5
    public static let dateSize: CGFloat = 10, timeSize: CGFloat = 12.5

    /// Widest sample texts reserved so the width does not fluctuate with the value.
    /// CPU is the most volatile value: room is reserved up to 100%. RAM and DISK rarely reach three digits; two digits keep the block compact.
    /// Depends on the language: the percent sign position, decimal separator and widest date (`_meta.dateTemplate`) vary.
    public static var cpuTemplate: String { Fmt.pct(100) }
    public static var valueTemplate: String { Fmt.pct(88) }
    public static var alertTemplate: String { "−" + Fmt.pct(88) }
    public static var netTemplate: String { "↓" + Fmt.dec1(88.8) }
    public static var dateTemplate: String { Localizer.shared.meta("dateTemplate", language: L10n.code) ?? "Wed, May 13, 2026" }
    public static var timeTemplate: String { Localizer.shared.meta("timeTemplate", language: L10n.code) ?? "88:88" }

    public enum Part: Equatable { case alert, metric(Int), net, clock }

    public static func model(_ s: Snapshot, now: Date, calendar: Calendar) -> StatusBlockModel {
        let metrics = [
            StatusMetric(label: L10n.t("menubar.cpu"), value: Fmt.pct(s.cpu.percent), level: Thresholds.cpuTotal(s.cpu.percent)),
            StatusMetric(label: L10n.t("menubar.ram"), value: Fmt.pct(s.memory.percent), level: s.memory.pressureLevel),
            StatusMetric(label: L10n.t("menubar.disk"), value: Fmt.pct(s.disk.percent), level: Thresholds.diskFree(s.disk.freeGB)),
        ]
        return StatusBlockModel(alert: alert(s), metrics: metrics,
                                down: "↓" + Fmt.rate(s.net.downMBps), up: "↑" + Fmt.rate(s.net.upMBps),
                                date: Fmt.menubarDate(now, calendar: calendar), time: String(Fmt.timeLine(now, calendar: calendar).prefix(5)))   // no seconds: redrawing every second doubled the idle cost
    }

    /// Heat, Battery and Docker have no permanent item; they appear inside the block when an incident occurs. If the chip is warm, heat shows
    /// on every incident (e.g. a CPU incident). Without sensors, the thermal state is shown instead of degrees.
    static func alert(_ s: Snapshot) -> StatusMetric? {
        guard let inc = s.incident else { return nil }
        if inc.kind == .heat || s.system.thermal != .ok {
            let value = s.capabilities.sensors ? Fmt.int(s.system.chipTemp) + "°" : s.system.thermal.thermalWord
            return StatusMetric(label: L10n.t("menubar.temp"), value: value, level: s.system.thermal == .ok ? inc.level : s.system.thermal)
        }
        if inc.kind == .battery, let drain = s.system.batteryDrain30m { return StatusMetric(label: L10n.t("menubar.battery"), value: "−" + Fmt.pct(drain), level: .warn) }
        if inc.kind == .docker {   // if not a percentage (restarting, unhealthy) a short status; the percent sign position depends on the language
            let v = inc.culpritValues.first ?? ""
            return StatusMetric(label: L10n.t("menubar.docker"), value: v.contains("%") || inc.level != .crit ? v : L10n.t("menubar.error"), level: inc.level)
        }
        return nil
    }

    /// Width of each part, left to right. `measure(text, pointSize, bold)`.
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

    public enum AlertTransition: Sendable { case appear, disappear }

    /// Appearance of an alert item appearing/disappearing (0.45 s, cubic-bezier(.2,.9,.3,1.2),
    /// 8 px from the right, scale 0.9). Disappearing is the reverse: 0.3 s, ease-in.
    public static func alertAppearance(_ kind: AlertTransition, elapsed: Double) -> (opacity: Double, dx: Double, scale: Double) {
        switch kind {
        case .appear:
            let k = cubicBezier(0.2, 0.9, 0.3, 1.2, elapsed / 0.45)
            return (min(1, max(0, k)), 8 * (1 - k), 0.9 + 0.1 * k)
        case .disappear:
            let k = cubicBezier(0.42, 0, 1, 1, elapsed / 0.3)
            return (1 - k, 8 * k, 1 - 0.1 * k)
        }
    }

    public static func alertAnimationDone(_ kind: AlertTransition, elapsed: Double) -> Bool {
        elapsed >= (kind == .appear ? 0.45 : 0.3)
    }

    /// CSS `cubic-bezier(x1, y1, x2, y2)` timing curve; `x` is progress (0…1).
    static func cubicBezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        func bx(_ t: Double) -> Double { 3 * (1 - t) * (1 - t) * t * x1 + 3 * (1 - t) * t * t * x2 + t * t * t }
        func by(_ t: Double) -> Double { 3 * (1 - t) * (1 - t) * t * y1 + 3 * (1 - t) * t * t * y2 + t * t * t }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<40 {
            if bx(t) < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return by(t)
    }

    /// Whether the status item's length should change: the new length if it must, `nil` if not.
    /// Thanks to the templates it is normally `nil`; it changes when an alert appears/disappears or a value exceeds its template.
    public static func newLength(_ m: StatusBlockModel, current: CGFloat, measure: (String, CGFloat, Bool) -> CGFloat) -> CGFloat? {
        let w = ceil(width(m, measure: measure))
        return w == current ? nil : w
    }

    public static func width(_ m: StatusBlockModel, measure: (String, CGFloat, Bool) -> CGFloat) -> CGFloat {
        let p = parts(m, measure: measure)
        return blockPadding * 2 + p.reduce(0) { $0 + $1.1 } + gap * CGFloat(p.count - 1) + clockGap
    }
}
