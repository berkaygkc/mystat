import MystatCore
import SwiftUI

/// Liquid Glass kenar menüsü (mockup `.sidebar`).
struct Sidebar<Source: MetricsSource>: View {
    let source: Source
    @Bindable var state: MonitorState

    static var items: [(MonitorSection, String, String)] {
        [(.overview, "Genel Bakış", "square.grid.2x2"), (.cpu, "İşlemci", "cpu"), (.mem, "Bellek", "memorychip"),
         (.disk, "Disk", "internaldrive"), (.net, "Ağ", "arrow.up.arrow.down"), (.docker, "Docker", "shippingbox"),
         (.sys, "Sistem", "thermometer.medium")]
    }

    var body: some View {
        let s = source.snapshot
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(Self.items.enumerated()), id: \.offset) { i, item in
                row(item.0, item.1, item.2, s)
                if i == 0 { Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, 10).padding(.vertical, 8) }
            }
            Spacer(minLength: 12)
            if let inc = s.incident { incidentCard(inc, s) }
            Text("MacBook Pro · M4 Pro\n14 çekirdek · 48 GB · açık 3 gün")
                .font(.system(size: 11)).lineSpacing(5).foregroundStyle(Theme.ink3)
                .padding(.horizontal, 10).padding(.top, 8)
        }
        .padding(.horizontal, 8).padding(.top, 48).padding(.bottom, 12)
        .frame(width: 236)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebarFill, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }

    private func row(_ id: MonitorSection, _ title: String, _ icon: String, _ s: Snapshot) -> some View {
        let v = MonitorPresentation.navValue(id.rawValue, s)
        let on = state.section == id
        return HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13, weight: .regular)).foregroundStyle(Theme.ink2).frame(width: 18)
            Text(title).font(.system(size: 13.5, weight: on ? .semibold : .medium)).foregroundStyle(Theme.ink)
            Spacer()
            Text(v.text).font(.system(size: 12, weight: v.level == .ok ? .medium : .semibold).monospacedDigit())
                .foregroundStyle(v.level == .ok ? Theme.ink3 : Theme.levelColor(v.level))
        }
        .padding(.horizontal, 10).frame(height: 34)
        .background(on ? Theme.sel : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { state.go(id) }
    }

    private func incidentCard(_ inc: Incident, _ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Kicker("OLAY · \(inc.minutes) DK", level: inc.level, pulsing: true)
            Text(String(GroupPresentation.panelHeadline(s).title.characters))
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.ink).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.redSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.redEdge, lineWidth: 0.5))
        .padding(.horizontal, 2).padding(.bottom, 10)
        .contentShape(Rectangle())
        .onTapGesture { state.go(MonitorSection(rawValue: MonitorPresentation.section(for: inc.kind)) ?? .cpu) }
    }
}
