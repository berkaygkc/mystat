import MystatCore
import SwiftUI

public enum MonitorSection: String, CaseIterable, Sendable {
    case overview, cpu, mem, disk, net, docker, sys
}

/// Menü çubuğuna tıklayınca açılan panel (mockup panel-menubar.html, D sütunu).
public struct PanelView<Source: MetricsSource>: View {
    let source: Source
    let openMonitor: (MonitorSection?, String?) -> Void

    public init(source: Source, openMonitor: @escaping (MonitorSection?, String?) -> Void) {
        self.source = source; self.openMonitor = openMonitor
    }

    public var body: some View {
        let s = source.snapshot
        let head = GroupPresentation.panelHeadline(s)
        let level = s.incident?.level ?? .ok
        VStack(alignment: .leading, spacing: 0) {
            Kicker(head.kicker, level: level, pulsing: s.incident != nil, tintText: false)
                .padding(.bottom, 8)
            Headline(head.title, size: 23, level: level == .ok ? .crit : level)
            Text(head.lede)
                .font(.system(size: 13.5)).lineSpacing(13.5 * 0.45 - 4)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)
            if s.incident != nil { culprits(s, level: level).padding(.top, 16).padding(.bottom, 4) }
            cells(s).padding(.top, 16)
            suggestions(s).padding(.top, 14)
            footer.padding(.top, 14)
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 16)
        .frame(width: 352, alignment: .leading)
        .background(Theme.panelFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func culprits(_ s: Snapshot, level: Level) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(PanelPresentation.culprits(s).enumerated()), id: \.offset) { i, r in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ink3).frame(width: 16, alignment: .leading)
                    Text("\(Text(r.name).font(.system(size: 13.5, weight: .semibold)).foregroundColor(Theme.ink))\(Text(r.context.isEmpty ? "" : "  " + r.context).font(.system(size: 13.5)).foregroundColor(Theme.ink2))")
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 6)
                    Text("\(Text(r.value).font(.system(size: 13.5, weight: .semibold).monospacedDigit()).foregroundColor(Theme.levelColor(level)))\(Text(" " + r.unit).font(.system(size: 11.5)).foregroundColor(Theme.ink3))")
                        .fixedSize()
                }
                .padding(.vertical, 8)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                .contentShape(Rectangle())
                .onTapGesture { openMonitor(sectionFor(s.incident?.kind), r.groupID) }
            }
        }
    }

    private func cells(_ s: Snapshot) -> some View {
        let cells = PanelPresentation.cells(s)
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    cell(cells[row * 2], left: true)
                    cell(cells[row * 2 + 1], left: false)
                }
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func cell(_ c: PanelCell, left: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(Text(c.big).font(.system(size: 30, weight: .light).monospacedDigit()).foregroundColor(c.level == .ok ? Theme.ink : Theme.levelColor(c.level)))\(Text(c.unit.map { " " + $0 } ?? "").font(.system(size: 15)).foregroundColor(Theme.ink3))")
                .tracking(-0.9).lineLimit(1)
            Text(c.label).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.ink).padding(.top, 6)
            Text(c.sub).font(.system(size: 11.5)).foregroundStyle(Theme.ink2).lineLimit(1).truncationMode(.tail).padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 13).padding(.bottom, 12)
        .padding(left ? .trailing : .leading, left ? 14 : 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .overlay(alignment: .trailing) { if left { Rectangle().fill(Theme.line).frame(width: 1) } }
        .contentShape(Rectangle())
        .onTapGesture { openMonitor(MonitorSection(rawValue: c.section), nil) }
    }

    private func suggestions(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BİR DE ŞUNLAR VAR").font(Theme.Fonts.kicker()).tracking(1.68).foregroundStyle(Theme.ink3).padding(.bottom, 4)
            ForEach(Array(s.suggestions.prefix(2).enumerated()), id: \.offset) { _, sg in
                HStack(spacing: 8) {
                    Text("→").foregroundStyle(Theme.ink3)
                    Text(sg.title).foregroundStyle(Theme.ink2).lineLimit(1)
                }
                .font(.system(size: 12.5)).padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture { openMonitor(target(sg.target).0, target(sg.target).1) }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Monitörü aç →").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                .contentShape(Rectangle()).onTapGesture { openMonitor(nil, nil) }
            Spacer()
            Text("⌘M").font(.system(size: 12)).foregroundStyle(Theme.ink3)
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func sectionFor(_ k: IncidentKind?) -> MonitorSection {
        switch k { case .memory: .mem; case .disk: .disk; case .docker: .docker; case .heat, .battery: .sys; default: .cpu }
    }

    private func target(_ t: SuggestionTarget) -> (MonitorSection, String?) {
        switch t { case .group(let id): (.cpu, id); case .docker: (.docker, nil); case .disk: (.disk, nil) }
    }
}
