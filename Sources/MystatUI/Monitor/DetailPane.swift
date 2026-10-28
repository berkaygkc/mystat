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
            if g.isOrphan { note("Bu sunucuyu başlatan terminal kapanmış, sunucu tek başına çalışmaya devam ediyor.") }
            if g.isDocker { note("Container'lar Docker'ın sanal makinesinde çalışıyor; ayrıntılar Docker bölümünde.") }
            if let rel {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AYNI PROJEDE").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(Theme.ink3)
                    Text("\(Text(rel.name).fontWeight(.semibold).foregroundColor(Theme.ink)) · \(rel.context) — \(Fmt.cores(rel.cpuCores)) çekirdek")
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
                Btn("Teşhisi kopyala", icon: "doc.on.doc", style: .primary) {
                    state.copyDiagnosis(GroupPresentation.diagnosis(g, incident: s.incident))
                }
                if g.isDocker {
                    Btn("Docker'da aç", trailing: "chevron.right") { state.go(.docker) }
                } else {
                    HStack(spacing: 7) {
                        Btn("Durdur") { state.confirm = Actions.stop(g, force: false) }
                        Btn("Zorla kapat", style: .danger) { state.confirm = Actions.stop(g, force: true) }
                    }
                }
            }
            .padding(.top, 16)
        }
        .frame(width: 300, alignment: .leading)
    }

    private func facts(_ g: ProcessGroup) -> [(String, String)] {
        var f = [("İşlemci", "\(Fmt.cores(g.cpuCores)) çekirdek"), ("Bellek", Fmt.mem(g.memoryGB)), ("Açık kalma", g.uptime), ("Süreç sayısı", String(g.processCount))]
        if let p = g.port { f.append(("Port", ":\(p)")) }
        if let d = g.folder { f.append(("Klasör", d)) }
        if let t = g.terminal { f.append(("Terminal", t)) }
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

/// Onay pencereleri ve eylem metinleri (mockup `askKill`, `askPrune`). Faz 1'de yalnızca bildirim gösterilir.
@MainActor
public enum Actions {
    public static func stop(_ g: ProcessGroup, force: Bool) -> ConfirmRequest {
        let who = g.name + (g.context.isEmpty ? "" : " · " + g.context)
        return ConfirmRequest(
            title: "\(who) " + (force ? "zorla kapatılsın mı?" : "durdurulsun mu?"),
            message: "\(g.processCount) süreç " + (force ? "hemen sonlandırılacak. Kaydedilmemiş iş varsa kaybolur."
                                                         : "kapanması için uyarılacak. Cevap vermezse zorla kapatmayı seçebilirsin."),
            confirm: force ? "Zorla kapat" : "Durdur", destructive: force,
            onConfirm: { ToastCenter.shared.show("\(g.name) " + (force ? "zorla kapatıldı (örnek)" : "durduruldu (örnek)")) })
    }
}
