import MystatCore
import SwiftUI

/// Ağ (mockup `secNet`).
struct NetworkSection<Source: MetricsSource>: View {
    let source: Source
    @Bindable var state: MonitorState

    var body: some View {
        let s = source.snapshot
        let down = source.series(.netDown, range: state.range)
        VStack(alignment: .leading, spacing: 0) {
            SectionHead("AĞ", title: title(s), lede: SectionText.networkLede(s))
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    SecH(title: "Trafik") { Legend(items: [("İndirme", Theme.chart), ("Gönderme", Theme.c1)]) }
                    AreaChart(series: [ChartSeries(down, color: Theme.chart, fill: true, name: "indirme"),
                                       ChartSeries(source.series(.netUp, range: state.range), color: Theme.c1, name: "gönderme")],
                              height: 180, range: state.range, format: { Fmt.rate($0) + " MB/s" }, formatY: { Fmt.int($0) + " MB/s" })
                    StatsRow(items: [("Bugün indirilen", Fmt.dec1(s.net.todayDownGB) + " GB", nil),
                                     ("Bugün gönderilen", Fmt.dec1(s.net.todayUpGB) + " GB", nil),
                                     ("Zirve (bu aralık)", Fmt.rate(down.max() ?? 0) + " MB/s", nil),
                                     ("Gecikme", Fmt.int(s.net.latencyMs) + " ms", "yönlendirici")])
                }
            }
            .padding(.top, 26)
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 0) {
                    SecH("Kim kullanıyor", note: "uygulamaya göre")
                    GroupList(groups: s.groups, metric: .network, state: state)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Bağlantı").font(.system(size: 18, weight: .semibold)).tracking(-0.27).foregroundStyle(Theme.ink)
                    Text("\(s.net.iface) · \(s.net.ssid)").font(.system(size: 12.5)).foregroundStyle(Theme.ink2).padding(.top, 3)
                    VStack(spacing: 0) { ForEach(s.net.details, id: \.label) { FactRow(k: $0.label, v: $0.value) } }.padding(.top, 12)
                    Text("Dış IP adresi, bir dış servise sormak gerektiği için varsayılan olarak gösterilmiyor.")
                        .font(.system(size: 12)).lineSpacing(3).foregroundStyle(Theme.ink3).padding(.top, 12).fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 300, alignment: .leading)
            }
            .padding(.top, 26)
        }
    }

    private func title(_ s: Snapshot) -> AttributedString {
        var unit = AttributedString(" MB/s"); unit.foregroundColor = Theme.ink3
        return AttributedString("↓ " + Fmt.rate(s.net.downMBps)) + unit + AttributedString("   ↑ " + Fmt.rate(s.net.upMBps)) + unit
    }
}
