import MystatCore
import SwiftUI

public enum MonitorSection: String, CaseIterable, Sendable {
    case overview, cpu, mem, disk, net, docker, sys
}

/// The panel that opens when the menu bar item is clicked.
public struct PanelView<Source: MetricsSource>: View {
    let source: Source
    let openMonitor: (MonitorSection?, String?) -> Void
    @Environment(\.colorScheme) private var scheme

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
            if s.incident != nil {   // line breaks matching the intended layout (push-out disabled); the calm one-line headline stays in SwiftUI
                PlainBreakText(text: PlainBreakText.headline(head.title, size: 23, level: level == .ok ? .crit : level))
            } else {
                Headline(head.title, size: 23, level: level == .ok ? .crit : level)
            }
            Text(head.lede)
                .font(.system(size: 13.5)).lineSpacing(13.5 * 0.45 - 4)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)
            if s.incident != nil { culprits(s, level: level).padding(.top, 16).padding(.bottom, 4) }
            cells(s).padding(.top, 16)
            suggestions(s).padding(.top, 14)
            footer.padding(.top, 14)
            HoverLink { on in
                Text(UIText.quit).font(.system(size: 12.5)).foregroundStyle(on ? Theme.ink : Theme.ink3).underline(on)
            }
            .onTapGesture { NSApp.terminate(nil) }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) { LanguageMenu() }   // does not change the row height
            .padding(.top, 10)
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 16)
        .frame(width: 352, alignment: .leading)
        .background(Theme.panelFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .background { PanelShadow(dark: scheme == .dark) }
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
                .modifier(HoverFill(inset: EdgeInsets(top: 2, leading: -8, bottom: 2, trailing: -8)))
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
        .modifier(HoverFill(inset: EdgeInsets(top: 4, leading: left ? -8 : 6, bottom: 4, trailing: left ? 6 : -8)))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .overlay(alignment: .trailing) { if left { Rectangle().fill(Theme.line).frame(width: 1) } }
        .contentShape(Rectangle())
        .onTapGesture { openMonitor(MonitorSection(rawValue: c.section), nil) }
    }

    private func suggestions(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("panel.also")).font(Theme.Fonts.kicker()).tracking(1.68).foregroundStyle(Theme.ink3).padding(.bottom, 4)
            ForEach(Array(s.suggestions.prefix(2).enumerated()), id: \.offset) { _, sg in
                HoverLink { on in
                    HStack(spacing: 8) {
                        Text("→").foregroundStyle(on ? Theme.ink2 : Theme.ink3).offset(x: on ? 2 : 0)
                        Text(sg.title).foregroundStyle(on ? Theme.ink : Theme.ink2).underline(on).lineLimit(1)
                    }
                    .font(.system(size: 12.5)).padding(.vertical, 4)
                }
                .onTapGesture { openMonitor(target(sg.target).0, target(sg.target).1) }
            }
        }
    }

    private var footer: some View {
        HStack {
            HoverLink { on in
                HStack(spacing: 4) {
                    Text(L10n.t("panel.openMonitor")).underline(on)
                    Text("→").offset(x: on ? 2 : 0)
                }
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            }
            .onTapGesture { openMonitor(nil, nil) }
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

/// The panel's outer shadow (0 30 70, 0 4 14). The window's own shadow is off: it was drawn for the square window
/// rather than the rounded panel. Since the panel's interior is translucent, the shadow stays outside only.
private struct PanelShadow: View {
    let dark: Bool
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        let tint = dark ? Color.black : Color(red: 12 / 255, green: 20 / 255, blue: 48 / 255)
        ZStack {
            shape.fill(.black).shadow(color: tint.opacity(dark ? 0.5 : 0.30), radius: 35, y: 30)
            shape.fill(.black).shadow(color: tint.opacity(dark ? 0.3 : 0.12), radius: 7, y: 4)
            shape.strokeBorder(.black.opacity(dark ? 0.6 : 0.07), lineWidth: 0.5).padding(-0.5)
        }
        .mask {
            Rectangle().padding(-160)
                .overlay { shape.blendMode(.destinationOut) }
                .compositingGroup()
        }
        .allowsHitTesting(false)
    }
}

/// Clickable row/tile: soft highlight and a pointing-hand cursor on hover.
private struct HoverFill: ViewModifier {
    let inset: EdgeInsets
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.hover)
                    .padding(inset).opacity(on ? 1 : 0)
            }
            .contentShape(Rectangle())
            .onHover { on = $0 }
            .pointerStyle(.link)
            .animation(.easeOut(duration: 0.15), value: on)
    }
}

/// Text link: underline on hover, arrow moves 2 pt forward, and a pointing-hand cursor.
private struct HoverLink<Label: View>: View {
    @ViewBuilder let label: (Bool) -> Label
    @State private var on = false
    var body: some View {
        label(on)
            .contentShape(Rectangle())
            .onHover { on = $0 }
            .pointerStyle(.link)
            .animation(.easeOut(duration: 0.15), value: on)
    }
}

/// Rule for clicks outside the panel. Clicks on the app's own windows count too,
/// except the panel's interior and the status item (which already toggles the panel).
/// The window is larger than the panel to fit the drawn shadow: clicking the shadow margin also counts as outside.
public enum PanelDismissal {
    public static func closes(clickWindow: NSWindow?, panel: NSWindow?, statusWindow: NSWindow?,
                              location: CGPoint = .zero, content: CGRect? = nil) -> Bool {
        guard let w = clickWindow else { return true }
        if w === panel { return content.map { !$0.contains(location) } ?? false }
        return w !== statusWindow
    }
}
