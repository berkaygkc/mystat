import AppKit
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
        let onBattery = !sys.onAC
        VStack(alignment: .leading, spacing: 0) {
            SectionHead("SİSTEM", title: h.title, lede: h.lede, level: h.level, pulsing: h.level != .ok)
            if let k = s.incident?.kind, k == .heat || k == .battery { IncidentBlock(source: source, state: state, inOverview: false).padding(.top, 20) }
            HStack(alignment: .top, spacing: 16) {
                if s.capabilities.sensors {
                    card(title: "Isı ve fan", pill: Pill(text: warm ? "Ilık" : "Normal", level: sys.thermal),
                         big: Fmt.int(sys.chipTemp), unit: "°C", bigLevel: sys.thermal,
                         label: "Çip ortalaması · fan " + SystemPresentation.fanText(sys),
                         series: ChartSeries(source.series(.temp, range: state.range), color: warm ? Theme.orange : Theme.chart, fill: true, name: "°C"),
                         max: 105, format: { Fmt.int($0) + "°" },
                         facts: [("İşlemci", Fmt.int(sys.chipTemp) + "°"), ("GPU", degrees(sys.gpuTemp)), ("SSD", degrees(sys.ssdTemp)),
                                 ("Yavaşlatma", warm ? "Henüz yok" : "Yok")])
                } else {
                    // Sensörler 2c'de: sahte sıcaklık yerine termal durum.
                    card(title: "Isı ve fan", pill: Pill(text: sys.thermal.thermalWord, level: sys.thermal),
                         big: "—", unit: "", bigLevel: .ok, label: "sensörler bağlanmadı",
                         series: ChartSeries([], color: Theme.chart, fill: true, name: "°C"), max: 105, format: { Fmt.int($0) + "°" },
                         facts: [("Yavaşlatma", sys.thermal == .crit ? "Var" : "Yok")])
                }
                card(title: "Güç ve pil", pill: Pill(text: onBattery ? "Pilde" : "Prizde", level: onBattery ? .warn : .ok),
                     big: String(sys.battery), unit: "%", bigLevel: onBattery ? .warn : .ok,
                     label: s.capabilities.sensors && sys.watts > 0 ? (sys.battery == 100 ? "Tam dolu" : "Pil") + " · şu an \(Fmt.int(sys.watts)) W harcanıyor"
                                                   : sys.charging && sys.battery < 100 ? "Şarj oluyor" : sys.battery == 100 ? "Tam dolu" : "Pil",
                     series: ChartSeries(s.capabilities.sensors ? source.series(.power, range: state.range) : [], color: Theme.chart, fill: true, name: "W"),
                     max: 100, format: { Fmt.int($0) + " W" },
                     facts: [("Adaptör", sys.adapter), ("Pil sağlığı", sys.health), ("Döngü", String(sys.cycles)), ("Kapasite", sys.capacity)])
                if s.capabilities.sensors {
                    let pill = SystemPresentation.gpuPill(sys)
                    card(title: "GPU", pill: Pill(text: pill.0, level: pill.1),
                         big: Fmt.int(sys.gpuPercent), unit: "%", bigLevel: pill.1,
                         label: "\(sys.gpuCores) çekirdekli GPU" + (sys.gpuTemp > 0 ? " · \(Fmt.int(sys.gpuTemp))°" : ""),
                         series: ChartSeries(source.series(.gpu, range: state.range), color: Theme.chart, fill: true, name: "GPU"),
                         max: 100, format: Fmt.pct,
                         facts: SystemPresentation.gpuFacts(withDisplays(sys)))
                } else {
                    card(title: "GPU", pill: Pill(text: "—", level: .ok), big: "—", unit: "", bigLevel: .ok, label: "sensörler bağlanmadı",
                         series: ChartSeries([], color: Theme.chart, fill: true, name: "GPU"), max: 100, format: Fmt.pct, facts: [])
                }
            }
            .padding(.top, 22)
            if s.capabilities.sensors { energy(s).padding(.top, 26) }   // süreç enerjisi 2c'de
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

    private func degrees(_ t: Double) -> String { t > 0 ? Fmt.int(t) + "°" : "—" }

    /// Canlı kaynak ekran sayısını bilmez; arayüz NSScreen'den tamamlar (örnek veride sabit 2).
    private func withDisplays(_ s: SystemState) -> SystemState {
        var s = s
        if s.displays == 0 { s.displays = NSScreen.screens.count }
        return s
    }

    private func energy(_ s: Snapshot) -> some View {
        let top = SystemPresentation.energyTop(s.groups, n: 5)
        let maxW = max(0.001, top.first?.watts ?? 1)
        return VStack(alignment: .leading, spacing: 0) {
            SecH("En çok enerji harcayanlar", note: "son 10 dk")   // grup watt'ı 10 dk penceresinin ortalaması
            ForEach(Array(top.enumerated()), id: \.offset) { i, g in
                HStack(spacing: 10) {
                    Text("\(i + 1)").foregroundStyle(Theme.ink3).frame(width: 16, alignment: .leading)
                    Text("\(Text(g.name).fontWeight(.semibold).foregroundColor(Theme.ink))  \(Text(g.context).foregroundColor(Theme.ink2))")
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Bar(fraction: g.watts / maxW, color: g.cpuCores >= 2 ? Theme.red : Theme.chart.opacity(0.7), height: 4).frame(width: 140)
                    Text(SystemPresentation.wattsText(g)).monospacedDigit().foregroundStyle(Theme.ink2).frame(width: 70, alignment: .trailing)
                }
                .font(.system(size: 13)).padding(.vertical, 9).hairlineTop(Theme.line2)
                .contentShape(Rectangle())
                .onTapGesture { state.select(.cpu, g.id) }
            }
        }
    }
}
