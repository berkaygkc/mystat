import MystatCore
import SwiftUI

/// Memory section.
struct MemorySection<Source: MetricsSource>: View {
    let source: Source
    @Bindable var state: MonitorState

    var body: some View {
        let s = source.snapshot, m = s.memory
        let h = SectionText.memory(s)
        let parts: [(String, Double, Color)] = [(L10n.t("mem.apps"), m.apps, Theme.c1), (L10n.t("section.sys"), m.wired, Theme.c2),
                                                (L10n.t("fact.compressed"), m.compressed, Theme.c3), (L10n.t("mem.freeCache"), m.free, Theme.c4)]
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(UIText.sectionKicker(.mem), title: h.title, soft: h.soft, lede: h.lede, level: h.level, pulsing: h.level != .ok)
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
                    SecH(title: L10n.t("mem.chart.title")) { Legend(items: [(L10n.t("legend.used"), Theme.chart), (L10n.t("fact.pressure"), Theme.c1)]) }
                    AreaChart(series: [ChartSeries(source.series(.memUsed, range: state.range), color: Theme.chart, fill: true, name: L10n.t("series.used")),
                                       ChartSeries(source.series(.memPressure, range: state.range), color: Theme.c1, name: L10n.t("series.pressure"))],
                              max: 100, height: 170, range: state.range, format: Fmt.pct, formatY: Fmt.pct)
                    StatsRow(items: [(L10n.t("fact.pressure"), PanelPresentation.pressureWord(m.pressureLevel).capitalized(with: Fmt.locale), Fmt.pct(m.pressurePercent)),
                                     (L10n.t("fact.swap"), Fmt.dec1(m.swapGB).replacingOccurrences(of: (Fmt.locale.decimalSeparator ?? ",") + "0", with: "") + " GB", nil),
                                     (L10n.t("fact.compressed"), Fmt.dec1(m.compressed) + " GB", nil),
                                     (L10n.t("mem.requested"), "≈ " + Fmt.int(m.apps + m.wired + m.compressed * 2.08) + " GB", L10n.t("mem.requested.sub"))])
                }
            }
            .padding(.top, 26)
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 0) {
                    SecH(L10n.t("mem.who"), note: L10n.t("mem.who.note"))
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
