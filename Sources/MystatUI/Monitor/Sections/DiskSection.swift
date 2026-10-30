import MystatCore
import SwiftUI

/// Disk section: usage, glass bubble map, sidebar and disk activity.
struct DiskSection<Source: MetricsSource>: View {
    let source: Source
    @Bindable var state: MonitorState

    var body: some View {
        let s = source.snapshot, disk = state.disk
        let h = SectionText.disk(s, home: source.diskTree.root, freedGB: disk.freedGB)
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(UIText.sectionKicker(.disk), title: h.title, soft: h.soft, lede: h.lede, level: h.level, pulsing: h.level != .ok)
            if s.incident?.kind == .disk { IncidentBlock(source: source, state: state, inOverview: false).padding(.top, 20) }
            usage(s).padding(.top, 16)
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 0) {
                    crumbs.padding(.bottom, 10)
                    DiskMapArea(disk: disk, scan: source.diskScan, scanAvailable: s.capabilities.diskScan,
                                accessNote: DiskPresentation.accessNote(fullDiskAccess: source.diskFullAccess, scanned: false, inaccessible: 0),
                                start: source.startDiskScan) { BubbleMapView(source: source, state: state) }
                }
                DiskSidePanel(source: source, disk: disk, state: state)
            }
            .padding(.top, 22)
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    SecH(title: L10n.t("disk.activity.title")) { Legend(items: [(L10n.t("legend.write"), Theme.chart), (L10n.t("legend.read"), Theme.chart2)]) }
                    AreaChart(series: [ChartSeries(source.series(.diskWrite, range: state.range), color: Theme.chart, fill: true, name: L10n.t("series.write")),
                                       ChartSeries(source.series(.diskRead, range: state.range), color: Theme.chart2, name: L10n.t("series.read"))],
                              height: 140, range: state.range, format: { Fmt.rate($0) + " MB/s" }, formatY: { Fmt.int($0) + " MB/s" })
                }
            }
            .padding(.top, 26)
        }
    }

    private func usage(_ s: Snapshot) -> some View {
        let d = s.disk
        let parts: [(String, Double, Color)] = [(L10n.t("disk.used"), d.usedGB, Theme.c1), (L10n.t("fact.purgeable"), d.purgeableGB, Theme.c3), (L10n.t("disk.free"), d.freeGB, Theme.c4)]
        return VStack(alignment: .leading, spacing: 10) {
            GeometryReader { g in
                let total = parts.reduce(0) { $0 + $1.1 }, gaps: CGFloat = 4
                HStack(spacing: 2) { ForEach(parts.indices, id: \.self) { i in Rectangle().fill(parts[i].2).frame(width: (g.size.width - gaps) * parts[i].1 / total) } }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(maxWidth: 760).frame(height: 12)
            HStack(alignment: .bottom, spacing: 20) {
                ForEach(parts.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).fill(parts[i].2).frame(width: 8, height: 8); Text(parts[i].0) }
                            .font(.system(size: 12)).foregroundStyle(Theme.ink2)
                        Text(Fmt.int(parts[i].1) + " GB").font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.ink)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(L10n.t("disk.activity")).font(.system(size: 12)).foregroundStyle(Theme.ink2)
                    Text("↑ \(Fmt.rate(d.writeMBps)) · ↓ \(Fmt.rate(d.readMBps)) MB/s").font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.ink)
                }
            }
        }
    }

    private var crumbs: some View {
        let disk = state.disk
        let parts = Breadcrumbs.make(disk.path)
        return HStack(spacing: 4) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, c in
                if i > 0 { Text("›").foregroundStyle(Theme.ink3) }
                let current = i == parts.count - 1
                Text(c.name).fontWeight(current ? .semibold : .regular).foregroundStyle(current ? Theme.ink : Theme.ink2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .help(c.isEllipsis ? L10n.t("disk.hiddenLevels") : "")
                    .contentShape(Rectangle())
                    .onTapGesture { if !current { disk.open(c.path) } }
            }
            Spacer()
            ScanStatus(scan: source.diskScan, note: DiskPresentation.accessNote(fullDiskAccess: source.diskFullAccess, scanned: true, inaccessible: source.diskInaccessible),
                       start: source.startDiskScan, stop: source.cancelDiskScan)
        }
        .font(.system(size: 13))
    }
}

/// Scan status at the trailing end of the path row: scanning / valid for X more minutes · Rescan.
struct ScanStatus: View {
    let scan: ScanPhase
    /// Number of folders that could not be read in the ready state (when Full Disk Access is missing).
    let note: String?
    let start: () -> Void
    let stop: () -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            HStack(spacing: 6) {
                switch scan.effective(now: ctx.date) {
                case .scanning(_, let gb, let path):
                    Text(L10n.t("disk.scanning", ["size": Fmt.size(gb), "path": path])).monospacedDigit().lineLimit(1).truncationMode(.middle)
                    Text(L10n.t("common.stop")).fontWeight(.semibold).foregroundStyle(Theme.ink2)
                        .onTapGesture { stop() }
                case .ready:
                    if let note {
                        Text(note + " ·").help(L10n.t("disk.fdaHelp"))
                    }
                    Text((scan.validityText(now: ctx.date) ?? "") + " ·")
                    Text(L10n.t("disk.rescan")).fontWeight(.semibold).foregroundStyle(Theme.ink2)
                        .onTapGesture { start() }
                case .none:
                    EmptyView()
                }
            }
            .font(.system(size: 12)).foregroundStyle(Theme.ink3)
        }
    }
}

/// Map card: states (empty / scanning / ready), thin progress line, glass Back button, legend, hint.
struct DiskMapArea<Map: View>: View {
    @Bindable var disk: DiskUIState
    let scan: ScanPhase
    /// The real scan is not wired up yet; until then the live source has no button.
    var scanAvailable = true
    /// Shown before scanning when Full Disk Access is missing.
    var accessNote: String?
    let start: () -> Void
    @Environment(\.openURL) private var openURL
    @ViewBuilder let map: () -> Map

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            let phase = scan.effective(now: ctx.date)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card)
                if case .none = phase { emptyState } else { map() }
                if case .scanning(let p, _, _) = phase {
                    GeometryReader { g in
                        Capsule().fill(Theme.acc).frame(width: g.size.width * p, height: 2).animation(.linear(duration: 0.1), value: p)
                    }
                    .frame(height: 2).padding(.horizontal, 20).padding(.top, 1)
                }
                if case .none = phase {} else { overlays }
            }
            .frame(height: 560)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.cardEdge, lineWidth: 0.5))
            .shadow(color: Color(red: 20 / 255, green: 20 / 255, blue: 60 / 255).opacity(0.10), radius: 25, y: 18)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Theme.c3).frame(width: 64, height: 64).offset(x: -18, y: 6)
                Circle().fill(Theme.c2).frame(width: 40, height: 40).offset(x: 24, y: -14)
                Circle().fill(Theme.kindColor(.regen).opacity(0.55)).frame(width: 26, height: 26).offset(x: 26, y: 22)
            }
            .frame(height: 90)
            Text(L10n.t("disk.map.title")).font(.system(size: 17, weight: .semibold)).tracking(-0.25).foregroundStyle(Theme.ink).padding(.top, 14)
            Text(L10n.t("disk.map.intro"))
                .font(.system(size: 13)).lineSpacing(3).multilineTextAlignment(.center).foregroundStyle(Theme.ink2)
                .frame(maxWidth: 340).padding(.top, 6)
            if scanAvailable {
                if let accessNote {
                    Text("\(Image(systemName: "lock"))  \(accessNote)")
                        .font(.system(size: 12.5)).lineSpacing(2).multilineTextAlignment(.center).foregroundStyle(Theme.ink3)
                        .frame(maxWidth: 340).padding(.top, 12)
                }
                HStack(spacing: 8) {
                    Btn(L10n.t("disk.scan.start"), icon: "magnifyingglass", style: .primary) { start() }
                    if accessNote != nil { Btn(L10n.t("net.ssid.openSettings"), icon: "gearshape") { openURL(DiskPresentation.settingsURL) } }
                }
                .fixedSize().padding(.top, 18)
            } else {
                Text(L10n.t("disk.scan.unavailable")).font(.system(size: 12.5)).foregroundStyle(Theme.ink3).padding(.top, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var overlays: some View {
        ZStack(alignment: .topLeading) {
            if !disk.path.isEmpty {
                Button { disk.open(Array(disk.path.dropLast())) } label: {
                    HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold)); Text(L10n.t("common.back")) }
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.ink)
                        .padding(.leading, 9).padding(.trailing, 14).frame(height: 30)
                        .background(Theme.tipFill, in: Capsule())
                        .glassEffect(.regular, in: Capsule())
                }
                .buttonStyle(.plain).padding(14)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
            Text(L10n.t("disk.map.hint")).font(.system(size: 11.5)).foregroundStyle(Theme.ink3)
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 16).padding(.top, 20)
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    ForEach([(NodeKind.folder, L10n.t("detail.folder")), (.regen, L10n.t("disk.kind.regen")), (.docker, "Docker"), (.file, L10n.t("disk.kind.file"))], id: \.1) { k, t in
                        HStack(spacing: 6) { Circle().fill(Theme.kindColor(k)).frame(width: 8, height: 8); Text(t) }
                    }
                }
                .font(.system(size: 11.5)).foregroundStyle(Theme.ink2)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Theme.tipFill, in: Capsule())
                .glassEffect(.regular, in: Capsule())
                .padding(14)
            }
        }
        .animation(.easeOut(duration: 0.3), value: disk.path.isEmpty)
    }
}
