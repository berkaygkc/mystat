import MystatCore
import SwiftUI

public struct ChartSeries {
    public let values: [Double]
    public let color: Color
    public let fill: Bool
    public let name: String
    public init(_ values: [Double], color: Color, fill: Bool = false, name: String) {
        self.values = values; self.color = color; self.fill = fill; self.name = name
    }
}

/// Mockup'taki `drawChart`: kesik ızgara, degrade dolgu, sağda %50/%100 etiketleri, altta eksen,
/// üzerine gelince dikey çizgi + noktalar + ipucu.
public struct AreaChart: View {
    let series: [ChartSeries]
    let fixedMax: Double?
    let height: CGFloat
    let range: TimeRange
    let format: (Double) -> String
    let formatY: ((Double) -> String)?
    let showGrid: Bool
    let showXAxis: Bool
    @State private var hoverX: CGFloat?

    public init(series: [ChartSeries], max: Double? = nil, height: CGFloat = 180, range: TimeRange,
                format: @escaping (Double) -> String, formatY: ((Double) -> String)? = nil,
                showGrid: Bool = true, showXAxis: Bool = true) {
        self.series = series; self.fixedMax = max; self.height = height; self.range = range
        self.format = format; self.formatY = formatY; self.showGrid = showGrid; self.showXAxis = showXAxis
    }

    public var body: some View {
        GeometryReader { proxy in
            let plotH = height - (showXAxis ? 20 : 2)
            let g = ChartGeometry(count: series.first?.values.count ?? 0, width: proxy.size.width, plotHeight: plotH,
                                  max: fixedMax ?? ChartGeometry.autoMax(series.map(\.values)))
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in draw(ctx, g) }
                if showGrid, let fy = formatY {
                    ForEach([0.5, 1.0], id: \.self) { f in
                        Text(fy(g.max * f)).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Theme.ink3)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .position(x: proxy.size.width / 2, y: g.labelY(fraction: f))
                    }
                }
                if showXAxis {
                    HStack { ForEach(range.axisLabels, id: \.self) { Text($0); if $0 != range.axisLabels.last { Spacer() } } }
                        .font(.system(size: 10.5)).foregroundStyle(Theme.ink3)
                        .frame(width: proxy.size.width).offset(y: height - 14)
                }
                if let hx = hoverX { hover(g, hx) }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let p) = phase { hoverX = p.x } else { hoverX = nil }
            }
        }
        .frame(height: height)
    }

    private func draw(_ ctx: GraphicsContext, _ g: ChartGeometry) {
        if showGrid {
            for f in [0.25, 0.5, 0.75] {
                let y = g.plotHeight * (1 - f)
                var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: g.width, y: y))
                ctx.stroke(p, with: .color(Theme.line2), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
        }
        for s in series where !s.values.isEmpty {
            var line = Path()
            for (i, v) in s.values.enumerated() {
                let pt = CGPoint(x: g.x(i), y: g.y(v))
                i == 0 ? line.move(to: pt) : line.addLine(to: pt)
            }
            if s.fill {
                var area = line
                area.addLine(to: CGPoint(x: g.width, y: g.plotHeight)); area.addLine(to: CGPoint(x: 0, y: g.plotHeight)); area.closeSubpath()
                ctx.fill(area, with: .linearGradient(Gradient(colors: [s.color.opacity(0.2), s.color.opacity(0)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: g.plotHeight)))
            }
            ctx.stroke(line, with: .color(s.color), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        }
    }

    @ViewBuilder
    private func hover(_ g: ChartGeometry, _ hx: CGFloat) -> some View {
        let i = g.index(atX: hx), px = g.x(i)
        Rectangle().fill(Theme.ink3).frame(width: 1, height: g.plotHeight).position(x: px, y: g.plotHeight / 2)
        ForEach(series.indices, id: \.self) { si in
            Circle().fill(series[si].color).frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(Theme.inv, lineWidth: 2))
                .position(x: px, y: g.y(series[si].values[min(i, series[si].values.count - 1)]))
        }
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                ForEach(series.indices, id: \.self) { si in
                    if si > 0 { Text("·").foregroundStyle(Theme.ink3) }
                    Text(format(series[si].values[min(i, series[si].values.count - 1)])).fontWeight(.semibold).monospacedDigit()
                    Text(series[si].name).foregroundStyle(Theme.ink3)
                }
            }
            Text(range.hoverLabel(index: i, now: Date(), calendar: .current)).foregroundStyle(Theme.ink3)
        }
        .font(.system(size: 11.5)).foregroundStyle(Theme.ink)
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Theme.tip, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.cardEdge, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 9, y: 6)
        .fixedSize()
        .alignmentGuide(.leading) { $0.width / 2 }
        .position(x: max(60, min(g.width - 60, px)), y: -26)
        .allowsHitTesting(false)
    }
}

/// Mockup'taki `sparkSVG`: küçük, eksensiz grafik.
public struct Sparkline: View {
    let values: [Double]
    let color: Color
    let height: CGFloat
    let fixedMax: Double?
    let fillOpacity: Double

    public init(_ values: [Double], color: Color, height: CGFloat = 30, max: Double? = nil, fillOpacity: Double = 0.18) {
        self.values = values; self.color = color; self.height = height; self.fixedMax = max; self.fillOpacity = fillOpacity
    }

    public var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let m = fixedMax ?? Swift.max(values.max() ?? 1, 0.0001) * 1.2
            let pts = values.enumerated().map { i, v in
                CGPoint(x: CGFloat(i) / CGFloat(values.count - 1) * size.width,
                        y: size.height - CGFloat(Swift.min(v, m) / m) * (size.height - 2) - 1)
            }
            var line = Path(); line.addLines(pts)
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height)); area.addLine(to: CGPoint(x: 0, y: size.height)); area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(fillOpacity), color.opacity(0)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(color), lineWidth: 1.5)
        }
        .frame(height: height)
    }
}
