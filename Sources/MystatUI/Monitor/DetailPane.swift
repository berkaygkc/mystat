import MystatCore
import SwiftUI

/// Seçili grubun detayı (mockup `detailPane`): olgular, aynı proje, teşhis ve kapatma.
public struct DetailPane<Source: MetricsSource>: View {
    let group: ProcessGroup
    let metric: GroupMetric
    let source: Source
    @Bindable var state: MonitorState
    @State private var relatedHover = false

    public init(group: ProcessGroup, metric: GroupMetric, source: Source, state: MonitorState) {
        self.group = group; self.metric = metric; self.source = source; self.state = state
    }

    public var body: some View {
        let s = source.snapshot
        let g = group
        let rel = GroupPresentation.related(of: g, in: s.groups)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text(g.name).font(.system(size: 18, weight: .semibold)).tracking(-0.27).foregroundStyle(Theme.ink)
                if g.isOrphan { OrphanBadge() }
            }
            Text(g.context.isEmpty ? " " : g.context).font(.system(size: 12.5)).foregroundStyle(Theme.ink2).padding(.top, 3)
            if metric == .cpu {
                Sparkline(Array(source.series(.group(g.id), range: state.range).suffix(60)),
                          color: g.cpuCores >= 2 ? Theme.red : Theme.chart, height: 54, fillOpacity: 0.2, capacity: 60)
                    .padding(.top, 12)
            }
            VStack(spacing: 0) { ForEach(facts(g), id: \.0) { fact($0.0, $0.1) } }.padding(.top, 10)
            if g.isOrphan { note(L10n.t("detail.orphanNote")) }
            if g.isDocker { note(L10n.t("detail.dockerNote")) }
            if let rel {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("detail.sameProject")).font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(Theme.ink3)
                    Text("\(Text(rel.name).fontWeight(.semibold).foregroundColor(Theme.ink)) · \(rel.context) — \(L10n.t("unit.coresValue", ["v": Fmt.cores(rel.cpuCores)]))")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.ink).lineSpacing(2)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(relatedHover ? Theme.sel : Theme.hover, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 12)
                .contentShape(Rectangle())
                .onHover { relatedHover = $0 }
                .onTapGesture { state.select(metric, rel.id) }
            }
            VStack(spacing: 7) {
                Btn(L10n.t("detail.copyDiagnosis"), icon: "doc.on.doc", style: .primary) {
                    state.copyDiagnosis(GroupPresentation.diagnosis(g, incident: s.incident))
                }
                if g.isDocker {
                    Btn(L10n.t("detail.openInDocker"), trailing: "chevron.right") { state.go(.docker) }
                } else {
                    HStack(spacing: 7) {
                        Btn(L10n.t("common.stop")) { state.confirm = Actions.stop(g, force: false, source: source) }
                        Btn(L10n.t("action.forceQuit"), style: .danger) { state.confirm = Actions.stop(g, force: true, source: source) }
                    }
                    .disabled(g.foreign)
                    .help(g.foreign ? StopOutcome.foreignReason : "")
                }
            }
            .padding(.top, 16)
            if g.foreign && !g.isDocker { note(StopOutcome.foreignReason) }
        }
        .frame(width: 300, alignment: .leading)
    }

    private func facts(_ g: ProcessGroup) -> [(String, String)] {
        var f = [(L10n.t("section.cpu"), L10n.t("unit.coresValue", ["v": Fmt.cores(g.cpuCores)])), (L10n.t("section.mem"), Fmt.mem(g.memoryGB)),
                 (L10n.t("detail.uptime"), g.uptime), (L10n.t("detail.processCount"), String(g.processCount))]
        if let p = g.port { f.append((L10n.t("detail.port"), ":\(p)")) }
        if let d = g.folder { f.append((L10n.t("detail.folder"), d)) }
        if let t = g.terminal { f.append((L10n.t("detail.terminal"), t)) }
        return f
    }

    private func fact(_ k: String, _ v: String) -> some View {
        HStack(spacing: 12) {
            Text(k).foregroundStyle(Theme.ink2)
            Spacer(minLength: 8)
            Text(v).fontWeight(.semibold).monospacedDigit().foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.head)
        }
        .font(.system(size: 12.5)).padding(.vertical, 8).hairlineTop(Theme.line2)
    }

    private func note(_ t: String) -> some View {
        Text(t).font(.system(size: 12)).lineSpacing(3).foregroundStyle(Theme.ink3).padding(.top, 12).fixedSize(horizontal: false, vertical: true)
    }
}

/// Onay pencereleri ve eylem metinleri (mockup `askKill`, `askPrune`). Onaylanınca kaynak durdurur, bildirim sonucu söyler.
@MainActor
public enum Actions {
    public static func stop(_ g: ProcessGroup, force: Bool, source: any MetricsSource) -> ConfirmRequest {
        let who = g.name + (g.context.isEmpty ? "" : " · " + g.context)
        return ConfirmRequest(
            title: L10n.t(force ? "action.forceQuit.title" : "action.stop.title", ["who": who]),
            message: L10n.plural(force ? "action.forceQuit.message" : "action.stop.message", g.processCount),
            confirm: L10n.t(force ? "action.forceQuit" : "common.stop"), destructive: force,
            onConfirm: { ToastCenter.shared.show(stopToast(g, force: force, source.stop(groupID: g.id, pids: g.pids, force: force))) })
    }

    static func stopToast(_ g: ProcessGroup, force: Bool, _ o: StopOutcome) -> String {
        switch o {
        case .done: L10n.t(force ? "action.toast.forceQuit" : "action.toast.stopped", ["name": g.name])
        case .notPermitted(let reason): reason
        case .notFound: L10n.t("action.toast.notFound", ["name": g.name])
        }
    }
}
