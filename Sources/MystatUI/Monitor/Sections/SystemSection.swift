import MystatCore
import SwiftUI

/// Sistem (mockup `secSys`).
struct SystemSection<Source: MetricsSource>: View {
    let source: Source
    @Bindable var state: MonitorState

    var body: some View {
        let s = source.snapshot, sys = s.system
        let h = SectionText.system(s)
        let warm = sys.thermal != .ok
        let onBattery = sys.batteryDrain30m != nil
        VStack(alignment: .leading, spacing: 0) {
            SectionHead("SİSTEM", title: h.title, lede: h.lede, level: h.level, pulsing: h.level != .ok)
            if let k = s.incident?.kind, k == .heat || k == .battery { IncidentBlock(source: source, state: state, inOverview: false).padding(.top, 20) }
            HStack(alignment: .top, spacing: 16) {
                card(title: "Isı ve fan", pill: Pill(text: warm ? "Ilık" : "Normal", level: sys.thermal),
                     big: Fmt.int(sys.chipTemp), unit: "°C", bigLevel: sys.thermal,
                     label: "Çip ortalaması · fan " + (sys.fanRPM > 0 ? Fmt.int(sys.fanRPM) + " dev/dk" : "duruyor"),
                     series: ChartSeries(source.series(.temp, range: state.range), color: warm ? Theme.orange : Theme.chart, fill: true, name: "°C"),
                     max: 105, format: { Fmt.int($0) + "°" },
                     facts: [("İşlemci", Fmt.int(sys.chipTemp) + "°"), ("GPU", Fmt.int(sys.gpuTemp) + "°"), ("SSD", Fmt.int(sys.ssdTemp) + "°"),
                             ("Yavaşlatma", warm ? "Henüz yok" : "Yok")])
                card(title: "Güç ve pil", pill: Pill(text: onBattery ? "Pilde" : "Prizde", level: onBattery ? .warn : .ok),
                     big: String(sys.battery), unit: "%", bigLevel: onBattery ? .warn : .ok,
                     label: (sys.battery == 100 ? "Tam dolu" : "Pil") + " · şu an \(Fmt.int(sys.watts)) W harcanıyor",
                     series: ChartSeries(source.series(.power, range: state.range), color: Theme.chart, fill: true, name: "W"),
                     max: 100, format: { Fmt.int($0) + " W" },
                     facts: [("Adaptör", sys.adapter), ("Pil sağlığı", sys.health), ("Döngü", String(sys.cycles)), ("Kapasite", sys.capacity)])
                card(title: "GPU", pill: Pill(text: "Sakin", level: .ok),
                     big: Fmt.int(sys.gpuPercent), unit: "%", bigLevel: .ok,
                     label: "\(sys.gpuCores) çekirdekli GPU · \(Fmt.int(sys.gpuTemp))°",
                     series: ChartSeries(source.series(.gpu, range: state.range), color: Theme.chart, fill: true, name: "GPU"),
                     max: 100, format: Fmt.pct,
                     facts: [("En çok kullanan", "WindowServer"), ("İkinci", "Brave Browser"), ("Bellek", "Paylaşımlı"), ("Ekranlar", "2")])
            }
            .padding(.top, 22)
            energy(s).padding(.top, 26)
        }
    }

    private func card(title: String, pill: Pill, big: String, unit: String, bigLevel: Level, label: String,
                      series: ChartSeries, max: Double, format: @escaping (Double) -> String, facts: [(String, String)]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                SecH(title: title) { pill }
                Text("\(Text(big).font(.system(size: 36, weight: .light).monospacedDigit()).foregroundColor(bigLevel == .ok ? Theme.ink : Theme.levelColor(bigLevel)))\(Text(unit).font(.system(size: 16)).foregroundColor(Theme.ink3))")
                    .tracking(-1).padding(.top, 6)
                Text(label).font(.system(size: 12)).foregroundStyle(Theme.ink2).padding(.top, 2)
                AreaChart(series: [series], max: max, height: 90, range: state.range, format: format, showGrid: false, showXAxis: false).padding(.top, 12)
                VStack(spacing: 0) { ForEach(facts, id: \.0) { FactRow(k: $0.0, v: $0.1) } }.padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func energy(_ s: Snapshot) -> some View {
        let top = GroupPresentation.sorted(s.groups, by: .cpu).prefix(5)
        let maxC = top.first?.cpuCores ?? 1
        return VStack(alignment: .leading, spacing: 0) {
            SecH("En çok enerji harcayanlar", note: "son \(state.range.title)")
            ForEach(Array(top.enumerated()), id: \.offset) { i, g in
                HStack(spacing: 10) {
                    Text("\(i + 1)").foregroundStyle(Theme.ink3).frame(width: 16, alignment: .leading)
                    Text("\(Text(g.name).fontWeight(.semibold).foregroundColor(Theme.ink))  \(Text(g.context).foregroundColor(Theme.ink2))")
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Bar(fraction: g.cpuCores / maxC, color: g.cpuCores >= 2 ? Theme.red : Theme.chart.opacity(0.7), height: 4).frame(width: 140)
                    Text(Fmt.dec1(g.cpuCores * 6.2) + " W").monospacedDigit().foregroundStyle(Theme.ink2).frame(width: 70, alignment: .trailing)
                }
                .font(.system(size: 13)).padding(.vertical, 9).hairlineTop(Theme.line2)
                .contentShape(Rectangle())
                .onTapGesture { state.select(.cpu, g.id) }
            }
        }
    }
}
