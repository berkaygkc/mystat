import MystatCore
import SwiftUI

/// "Kim yiyor" listesi (mockup `groupList`). Alt süreçler yalnızca İşlemci'de açılır.
public struct GroupList: View {
    let groups: [ProcessGroup]
    let metric: GroupMetric
    @Bindable var state: MonitorState
    @State private var hovered: String?

    public init(groups: [ProcessGroup], metric: GroupMetric, state: MonitorState) {
        self.groups = groups; self.metric = metric; self.state = state
    }

    private var unit: String { metric == .cpu ? "çekirdek" : metric == .network ? "MB/s" : "" }

    public var body: some View {
        let list = GroupPresentation.sorted(groups, by: metric)
        let maxV = list.map { GroupPresentation.value($0, metric) }.max() ?? 1
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Color.clear.frame(width: 18)
                Text(metric == .network ? "Uygulama" : "Uygulama / grup").frame(maxWidth: .infinity, alignment: .leading)
                Text(metric == .cpu ? "İşlemci payı" : metric == .network ? "Trafik payı" : "Bellek payı").frame(width: 120, alignment: .leading)
                Text(metric == .cpu ? "Çekirdek" : metric == .network ? "↓ İndirme" : "Bellek").frame(width: 92, alignment: .trailing)
            }
            .font(.system(size: 11)).foregroundStyle(Theme.ink3).padding(.horizontal, 10).padding(.bottom, 6)
            ForEach(list) { g in
                row(g, maxV)
                if metric == .cpu, state.expanded.contains(g.id), !g.children.isEmpty { kids(g) }
            }
        }
    }

    private func row(_ g: ProcessGroup, _ maxV: Double) -> some View {
        let v = GroupPresentation.value(g, metric)
        let hot = metric == .cpu && v >= 2
        let canOpen = metric == .cpu && !g.children.isEmpty
        let on = state.selected[metric] == g.id
        return HStack(spacing: 10) {
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.ink3)
                .rotationEffect(.degrees(state.expanded.contains(g.id) && canOpen ? 90 : 0))
                .opacity(canOpen ? 1 : 0).frame(width: 18)
                .contentShape(Rectangle())
                .onTapGesture { if canOpen { withAnimation(.easeOut(duration: 0.2)) { state.toggleExpanded(g.id) } } }
            HStack(spacing: 6) {
                Text(g.name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(g.context).font(.system(size: 12.5)).foregroundStyle(Theme.ink2)
                if g.isOrphan { OrphanBadge().padding(.leading, 1) }
            }
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Bar(fraction: maxV > 0 ? v / maxV : 0, color: hot ? Theme.red : Theme.chart.opacity(0.62), height: 4).frame(width: 120)
            Text("\(Text(metric == .memory ? Fmt.mem(v) : Fmt.cores(v)).fontWeight(.semibold).foregroundColor(hot ? Theme.red : Theme.ink))\(Text(unit.isEmpty ? "" : " " + unit).font(.system(size: 11)).foregroundColor(Theme.ink3))")
                .font(.system(size: 13.5).monospacedDigit()).frame(width: 92, alignment: .trailing)
        }
        .padding(.horizontal, 10).frame(minHeight: 46)
        .background(on ? Theme.sel : hovered == g.id ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? g.id : (hovered == g.id ? nil : hovered) }
        .onTapGesture { state.select(metric, g.id) }
    }

    @ViewBuilder
    private func kids(_ g: ProcessGroup) -> some View {
        let kmax = g.children.map(\.cpuCores).max() ?? 1
        ForEach(Array(g.children.prefix(5).enumerated()), id: \.offset) { _, k in
            HStack(spacing: 10) {
                Color.clear.frame(width: 18)
                Text(k.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Bar(fraction: kmax > 0 ? k.cpuCores / kmax : 0, color: Theme.chart2, height: 3).frame(width: 120)
                Text(Fmt.cores(k.cpuCores)).monospacedDigit().frame(width: 92, alignment: .trailing)
            }
            .font(.system(size: 12.5)).foregroundStyle(Theme.ink2)
            .padding(.leading, 38).padding(.trailing, 10).frame(height: 30)
        }
        if g.processCount > g.children.count {
            Text("+ \(g.processCount - g.children.count) küçük süreç daha").font(.system(size: 12)).foregroundStyle(Theme.ink3)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 66).padding(.top, 4).padding(.bottom, 8)
        }
    }
}
