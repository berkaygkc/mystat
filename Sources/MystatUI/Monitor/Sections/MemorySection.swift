import MystatCore
import SwiftUI

/// Bellek (mockup `secMem`).
struct MemorySection<Source: MetricsSource>: View {
    let source: Source
    @Bindable var state: MonitorState

    var body: some View {
        let s = source.snapshot, m = s.memory
        let h = SectionText.memory(s)
        let parts: [(String, Double, Color)] = [("Uygulamalar", m.apps, Theme.c1), ("Sistem", m.wired, Theme.c2),
                                                ("Sıkıştırılmış", m.compressed, Theme.c3), ("Boş ve önbellek", m.free, Theme.c4)]
        VStack(alignment: .leading, spacing: 0) {
            SectionHead("BELLEK", title: h.title, soft: h.soft, lede: h.lede, level: h.level, pulsing: h.level != .ok)
            if s.incident?.kind == .memory { IncidentBlock(source: source, state: state, inOverview: false).padding(.top, 20) }
            GeometryReader { g in
                let total = parts.reduce(0) { $0 + $1.1 }, gaps = CGFloat(parts.count - 1) * 2
                HStack(spacing: 2) {
                    ForEach(parts.indices, id: \.self) { i in
                        Rectangle().fill(parts[i].2).frame(width: (g.size.width - gaps) * parts[i].1 / total)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(height: 12).padding(.top, 14)
            HStack(spacing: 20) {
                ForEach(parts.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).fill(parts[i].2).frame(width: 8, height: 8); Text(parts[i].0) }
                            .font(.system(size: 12)).foregroundStyle(Theme.ink2)
                        Text(Fmt.dec1(parts[i].1) + " GB").font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.ink)
                    }
                }
            }
            .padding(.top, 10)
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    SecH(title: "Doluluk ve baskı") { Legend(items: [("Dolu", Theme.chart), ("Baskı", Theme.c1)]) }
                    AreaChart(series: [ChartSeries(source.series(.memUsed, range: state.range), color: Theme.chart, fill: true, name: "dolu"),
                                       ChartSeries(source.series(.memPressure, range: state.range), color: Theme.c1, name: "baskı")],
                              max: 100, height: 170, range: state.range, format: Fmt.pct, formatY: Fmt.pct)
                    StatsRow(items: [("Baskı", PanelPresentation.pressureWord(m.pressureLevel).capitalized(with: Fmt.locale), Fmt.pct(m.pressurePercent)),
                                     ("Swap", Fmt.dec1(m.swapGB).replacingOccurrences(of: ",0", with: "") + " GB", nil),
                                     ("Sıkıştırılmış", Fmt.dec1(m.compressed) + " GB", nil),
                                     ("Uygulamaların istediği", "≈ " + Fmt.int(m.apps + m.wired + m.compressed * 2.08) + " GB", "sıkıştırma öncesi")])
                }
            }
            .padding(.top, 26)
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 0) {
                    SecH("Kim tutuyor", note: "gerçek ayak izi, sıkıştırılmış dahil")
                    GroupList(groups: s.groups, metric: .memory, state: state)
                }
                if let g = s.groups.first(where: { $0.id == state.selected[.memory] }) {
                    DetailPane(group: g, metric: .memory, source: source, state: state)
                }
            }
            .padding(.top, 26)
        }
    }
}
