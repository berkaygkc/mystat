import MystatCore
import SwiftUI

/// Genel Bakış (mockup `secOverview`).
struct OverviewSection<Source: MetricsSource>: View {
    let source: Source
    @Bindable var state: MonitorState

    var body: some View {
        let s = source.snapshot
        let head = GroupPresentation.panelHeadline(s)
        VStack(alignment: .leading, spacing: 0) {
            SectionHead("ŞU AN", title: head.title, lede: MonitorPresentation.overviewLede(s),
                        level: s.incident?.level ?? .ok, pulsing: s.incident != nil)
            IncidentBlock(source: source, state: state, inOverview: true).padding(.top, s.incident == nil ? 0 : 20)
            tiles(s).padding(.top, 24)
            HStack(alignment: .top, spacing: 28) {
                topEaters(s).frame(maxWidth: .infinity).layoutPriority(1.45)
                suggestions(s).frame(maxWidth: .infinity)
            }
            .padding(.top, 26)
        }
    }

    private func tiles(_ s: Snapshot) -> some View {
        let cells = PanelPresentation.cells(s)
        let series: [(SeriesKey, Double?)] = [(.cpu, 100), (.memUsed, 100), (.diskWrite, nil), (.netDown, nil), (.dockerCPU, 100), (.temp, 105)]
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { col in
                        let i = row * 3 + col, c = cells[i]
                        tile(c, series: Array(source.series(series[i].0, range: state.range).suffix(60)), max: series[i].1, col: col)
                    }
                }
            }
        }
        .hairlineTop()
    }

    private func tile(_ c: PanelCell, series: [Double], max: Double?, col: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(Text(c.big).font(.system(size: 34, weight: .light).monospacedDigit()).foregroundColor(c.level == .ok ? Theme.ink : Theme.levelColor(c.level)))\(Text(c.unit.map { " " + $0 } ?? "").font(.system(size: 16)).foregroundColor(Theme.ink3))")
                .tracking(-1)
            Text(c.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink).padding(.top, 8)
            Text(c.sub).font(.system(size: 12)).foregroundStyle(Theme.ink2).lineLimit(1).padding(.top, 2)
            Sparkline(series, color: c.level == .ok ? Theme.chart : Theme.levelColor(c.level), height: 30, max: max).padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16).padding(.bottom, 14).padding(.leading, col == 0 ? 0 : 18).padding(.trailing, 18)
        .hairlineBottom()
        .overlay(alignment: .trailing) { if col < 2 { Rectangle().fill(Theme.line).frame(width: 1) } }
        .contentShape(Rectangle())
        .onTapGesture { state.go(MonitorSection(rawValue: c.section) ?? .overview) }
    }

    private func topEaters(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SecH("Şu an en çok yiyenler", note: "tüm makine")
            HStack(spacing: 10) {
                Text("Uygulama / grup").frame(maxWidth: .infinity, alignment: .leading)
                Text("İşlemci").frame(width: 86, alignment: .trailing)
                Text("Bellek").frame(width: 70, alignment: .trailing)
            }
            .font(.system(size: 11)).foregroundStyle(Theme.ink3).padding(.bottom, 6)
            ForEach(GroupPresentation.sorted(s.groups, by: .cpu).prefix(5)) { g in
                HStack(spacing: 10) {
                    Text("\(Text(g.name).fontWeight(.semibold).foregroundColor(Theme.ink))  \(Text(g.context).foregroundColor(Theme.ink2))")
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(Fmt.cores(g.cpuCores)) çek.").fontWeight(g.cpuCores >= 2 ? .semibold : .regular)
                        .foregroundStyle(g.cpuCores >= 2 ? Theme.red : Theme.ink2).frame(width: 86, alignment: .trailing)
                    Text(Fmt.mem(g.memoryGB)).foregroundStyle(Theme.ink2).frame(width: 70, alignment: .trailing)
                }
                .font(.system(size: 13).monospacedDigit()).padding(.vertical, 9).hairlineTop(Theme.line2)
                .contentShape(Rectangle())
                .onTapGesture { state.select(.cpu, g.id) }
            }
        }
    }

    private func suggestions(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SecH("Öneriler", note: "acil değil")
            ForEach(Array(s.suggestions.enumerated()), id: \.offset) { _, sg in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("→").foregroundStyle(Theme.ink3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sg.title).foregroundStyle(Theme.ink)
                        Text(sg.detail).font(.system(size: 12)).foregroundStyle(Theme.ink3)
                    }
                }
                .font(.system(size: 13)).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).hairlineTop(Theme.line2)
                .contentShape(Rectangle())
                .onTapGesture {
                    switch sg.target {
                    case .group(let id): state.select(.cpu, id)
                    case .docker: state.go(.docker)
                    case .disk: state.go(.disk)
                    }
                }
            }
        }
    }
}
