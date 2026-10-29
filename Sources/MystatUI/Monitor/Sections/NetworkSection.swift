import MystatCore
import SwiftUI

/// Ağ (mockup `secNet`).
struct NetworkSection<Source: MetricsSource>: View {
    let source: Source
    @Bindable var state: MonitorState
    @Environment(\.openURL) private var openURL

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
                                     ("Zirve (bu aralık)", Fmt.rate(down.filter(\.isFinite).max() ?? 0) + " MB/s", nil),
                                     ("Gecikme", s.capabilities.netDetails ? NetPresentation.latencyText(s.net.latencyMs) : "—", "yönlendirici")])
                }
            }
            .padding(.top, 26)
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 0) {
                    SecH("Kim kullanıyor", note: "uygulamaya göre")
                    let users = GroupPresentation.networkUsers(s.groups)
                    if s.capabilities.netDetails, !s.net.perAppAvailable {
                        Text("Uygulama bazında ağ okunamadı.").font(.system(size: 12.5)).foregroundStyle(Theme.ink3).padding(.top, 10)
                    } else if s.capabilities.netDetails, users.isEmpty {
                        Text("Şu an ağı kullanan bir uygulama yok.").font(.system(size: 12.5)).foregroundStyle(Theme.ink3).padding(.top, 10)
                    } else if s.capabilities.netDetails {
                        GroupList(groups: users, metric: .network, state: state)
                    } else {
                        Text("Uygulama bazında ağ kullanımı henüz bağlanmadı.").font(.system(size: 12.5)).foregroundStyle(Theme.ink3).padding(.top, 10)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Bağlantı").font(.system(size: 18, weight: .semibold)).tracking(-0.27).foregroundStyle(Theme.ink)
                    Text(s.net.ssid.isEmpty ? s.net.iface : "\(s.net.iface) · \(s.net.ssid)").font(.system(size: 12.5)).foregroundStyle(Theme.ink2).padding(.top, 3)
                    if let line = NetPresentation.accessLine(s.net.ssidAccess) {   // ağ adı için konum izni (yalnızca düğmeyle)
                        (Text(line.text + " ") + Text(line.action).fontWeight(.semibold).foregroundStyle(Theme.ink2))
                            .font(.system(size: 12)).lineSpacing(2).foregroundStyle(Theme.ink3).padding(.top, 6)
                            .fixedSize(horizontal: false, vertical: true)
                            .onTapGesture {
                                if s.net.ssidAccess == .denied { openURL(NetPresentation.locationSettingsURL) } else { source.requestNetworkNameAccess() }
                            }
                    }
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
