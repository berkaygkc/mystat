import MystatCore
import SwiftUI

/// Olay alanı (mockup `incidentBlock`): ne, ne zamandan beri, zirve, sorumlular, eylemler.
struct IncidentBlock<Source: MetricsSource>: View {
    let source: Source
    let state: MonitorState
    let inOverview: Bool

    var body: some View {
        if let inc = source.snapshot.incident {
            content(inc, source.snapshot)
        }
    }

    private func content(_ inc: Incident, _ s: Snapshot) -> some View {
        let rows = PanelPresentation.culprits(s)
        let maxV = rows.compactMap { Fmt.number($0.value) }.max() ?? 1
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 0) {
                    Kicker(L10n.plural("incident.kicker", inc.minutes), level: inc.level, pulsing: true).padding(.bottom, 8)
                    Text(MonitorPresentation.incidentSentence(s))
                        .font(.system(size: 17, weight: .semibold)).tracking(-0.25).lineSpacing(4).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 18) {
                        ForEach(inc.facts, id: \.label) { f in
                            Text("\(Text(f.label).foregroundColor(Theme.ink2)) \(Text(f.value).fontWeight(.semibold).foregroundColor(f.level == .ok ? Theme.ink : Theme.levelColor(f.level)))")
                        }
                    }
                    .font(.system(size: 12).monospacedDigit()).padding(.top, 10)
                }
                Sparkline(Array(source.series(MonitorPresentation.seriesKey(for: inc.kind), range: .m10).suffix(60)),
                          color: Theme.levelColor(inc.level), height: 64, max: inc.kind == .cpu ? 100 : nil, fillOpacity: 0.25, capacity: 60)
                    .frame(width: 260)
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    let v = Fmt.number(r.value) ?? 0
                    HStack(spacing: 10) {
                        Text("\(i + 1)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ink3).frame(width: 16, alignment: .leading)
                        Text("\(Text(r.name).fontWeight(.semibold).foregroundColor(Theme.ink))  \(Text(r.context).foregroundColor(Theme.ink2))")
                            .font(.system(size: 13.5)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Capsule().fill(Theme.line).frame(width: 120, height: 4)
                            .overlay(alignment: .leading) { Capsule().fill(Theme.levelColor(inc.level)).frame(width: 120 * min(1, v / maxV), height: 4) }
                        Text("\(Text(r.value).fontWeight(.semibold).foregroundColor(Theme.levelColor(inc.level))) \(Text(r.unit).font(.system(size: 11)).foregroundColor(Theme.ink3))")
                            .font(.system(size: 13.5).monospacedDigit()).frame(width: 92, alignment: .trailing)
                    }
                    .padding(.vertical, 7)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.redEdge).frame(height: 1) }
                    .contentShape(Rectangle())
                    .onTapGesture { state.show(MonitorSection(rawValue: MonitorPresentation.section(for: inc.kind)) ?? .cpu, group: r.groupID) }
                }
            }
            .padding(.top, 12)
            HStack(spacing: 8) {
                Btn(L10n.t("detail.copyDiagnosis"), icon: "doc.on.doc") {
                    if let g = s.groups.first(where: { $0.id == rows.first?.groupID }) {
                        state.copyDiagnosis(GroupPresentation.diagnosis(g, incident: inc))
                    }
                }.fixedSize()
                let sec = MonitorPresentation.section(for: inc.kind)
                Btn(inOverview ? MonitorPresentation.inspectTitle(section: sec) : L10n.t("incident.showCulprit"), trailing: "chevron.right") {
                    if inOverview { state.go(MonitorSection(rawValue: sec) ?? .cpu) }
                    else if let first = rows.first { state.show(MonitorSection(rawValue: sec) ?? .cpu, group: first.groupID) }
                }.fixedSize()
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 14)
        .background(Theme.redSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.redEdge, lineWidth: 0.5))
    }
}
