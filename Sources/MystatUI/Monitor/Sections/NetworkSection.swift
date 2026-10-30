import MystatCore
import SwiftUI

/// Network section.
struct NetworkSection<Source: MetricsSource>: View {
    let source: Source
    @Bindable var state: MonitorState
    @Environment(\.openURL) private var openURL

    var body: some View {
        let s = source.snapshot
        let down = source.series(.netDown, range: state.range)
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(UIText.sectionKicker(.net), title: title(s), lede: SectionText.networkLede(s))
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    SecH(title: L10n.t("net.traffic")) { Legend(items: [(L10n.t("legend.download"), Theme.chart), (L10n.t("legend.upload"), Theme.c1)]) }
                    AreaChart(series: [ChartSeries(down, color: Theme.chart, fill: true, name: L10n.t("series.download")),
                                       ChartSeries(source.series(.netUp, range: state.range), color: Theme.c1, name: L10n.t("series.upload"))],
                              height: 180, range: state.range, format: { Fmt.rate($0) + " MB/s" }, formatY: { Fmt.int($0) + " MB/s" })
                    StatsRow(items: [(L10n.t("net.todayDown"), Fmt.dec1(s.net.todayDownGB) + " GB", nil),
                                     (L10n.t("net.todayUp"), Fmt.dec1(s.net.todayUpGB) + " GB", nil),
                                     (L10n.t("stats.peakRange"), Fmt.rate(down.filter(\.isFinite).max() ?? 0) + " MB/s", nil),
                                     (L10n.t("net.latency"), s.capabilities.netDetails ? NetPresentation.latencyText(s.net.latencyMs) : "—", L10n.t("net.latency.sub"))])
                }
            }
            .padding(.top, 26)
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 0) {
                    SecH(L10n.t("net.who"), note: L10n.t("net.who.note"))
                    let users = GroupPresentation.networkUsers(s.groups)
                    if s.capabilities.netDetails,
                       let note = NetPresentation.perAppNote(available: s.net.perAppAvailable, ready: s.net.perAppReady, empty: users.isEmpty) {
                        Text(note).font(.system(size: 12.5)).foregroundStyle(Theme.ink3).padding(.top, 10)
                    } else if s.capabilities.netDetails {
                        GroupList(groups: users, metric: .network, state: state)
                    } else {
                        Text(L10n.t("net.perApp.notConnected")).font(.system(size: 12.5)).foregroundStyle(Theme.ink3).padding(.top, 10)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.t("net.connection")).font(.system(size: 18, weight: .semibold)).tracking(-0.27).foregroundStyle(Theme.ink)
                    Text(s.net.ssid.isEmpty ? s.net.iface : "\(s.net.iface) · \(s.net.ssid)").font(.system(size: 12.5)).foregroundStyle(Theme.ink2).padding(.top, 3)
                    if let line = NetPresentation.accessLine(s.net.ssidAccess) {   // location permission for the network name (button only)
                        (Text(line.text + " ") + Text(line.action).fontWeight(.semibold).foregroundStyle(Theme.ink2))
                            .font(.system(size: 12)).lineSpacing(2).foregroundStyle(Theme.ink3).padding(.top, 6)
                            .fixedSize(horizontal: false, vertical: true)
                            .onTapGesture {
                                if s.net.ssidAccess == .denied { openURL(NetPresentation.locationSettingsURL) } else { source.requestNetworkNameAccess() }
                            }
                    }
                    VStack(spacing: 0) { ForEach(s.net.details, id: \.label) { FactRow(k: $0.label, v: $0.value) } }.padding(.top, 12)
                    Text(L10n.t("net.publicIPNote"))
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
