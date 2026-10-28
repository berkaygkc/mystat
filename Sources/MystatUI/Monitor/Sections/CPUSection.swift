import MystatCore
import SwiftUI

/// İşlemci (mockup `secCPU`).
struct CPUSection<Source: MetricsSource>: View {
    let source: Source
    @Bindable var state: MonitorState

    var body: some View {
        let s = source.snapshot
        let h = GroupPresentation.cpuHeadline(s)
        let level = Thresholds.cpuTotal(s.cpu.percent)
        let hot = s.incident?.kind == .cpu
        let cpu = source.series(.cpu, range: state.range)
        VStack(alignment: .leading, spacing: 0) {
            SectionHead("İŞLEMCİ", title: h.title, soft: h.soft, lede: hot ? nil : MonitorPresentation.cpuCalmLede,
                        level: hot ? level : .ok, pulsing: hot)
            if hot { IncidentBlock(source: source, state: state, inOverview: false).padding(.top, 20) }
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    SecH(title: "Kullanım") { Legend(items: [("Toplam", Theme.chart), ("Sistem", Theme.chart2)]) }
                    AreaChart(series: [ChartSeries(cpu, color: hot ? Theme.red : Theme.chart, fill: true, name: "toplam"),
                                       ChartSeries(source.series(.cpuSystem, range: state.range), color: Theme.chart2, name: "sistem")],
                              max: 100, height: 190, range: state.range, format: Fmt.pct, formatY: Fmt.pct)
                    StatsRow(items: [("Kullanıcı", Fmt.pct(s.cpu.percent * 0.78), nil), ("Sistem", Fmt.pct(s.cpu.systemPercent), nil),
                                     ("Yük ortalaması", s.cpu.loadAvg.map(Fmt.dec1).joined(separator: " · "), nil),
                                     ("Zirve (bu aralık)", Fmt.pct(cpu.max() ?? 0), nil)])
                }
            }
            .padding(.top, 26)
            cores(s).padding(.top, 26)
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 0) {
                    SecH("Kim yiyor", note: "uygulama ve projeye göre gruplu")
                    GroupList(groups: s.groups, metric: .cpu, state: state)
                }
                if let g = s.groups.first(where: { $0.id == state.selected[.cpu] }) {
                    DetailPane(group: g, metric: .cpu, source: source, state: state)
                }
            }
            .padding(.top, 26)
        }
    }

    private func cores(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SecH("Çekirdekler", note: "10 performans · 4 verimlilik")
            HStack(spacing: 6) {
                ForEach(Array(s.cpu.cores.enumerated()), id: \.offset) { _, v in
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.line2)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(v > 85 ? Theme.red.opacity(0.78) : Theme.chart.opacity(0.32))
                                .frame(height: 46 * v / 100)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .frame(height: 46)
                }
            }
            HStack(spacing: 6) {
                ForEach(0..<s.cpu.cores.count, id: \.self) { i in
                    Text(i < 10 ? "P\(i + 1)" : "V\(i - 9)").frame(maxWidth: .infinity)
                }
            }
            .font(.system(size: 10)).foregroundStyle(Theme.ink3).padding(.top, 5)
        }
    }
}
