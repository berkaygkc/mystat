import AppKit
import MystatCore
import MystatUI
import SwiftUI

/// `mystat --snapshot <menubar|panel|monitor|bubbles|charts> --out x.png [--lang en|tr] [--scale 2] [--dark] [--incident] [--kind k] [--section s] [--size WxH] [--scan s]`
/// Draws the view in an off-screen window and writes it to PNG; for visual comparison.
@MainActor
enum SnapshotMode {
    struct Options {
        var target = "panel", out = "/tmp/mystat-snapshot.png"
        var dark = false, incident = false
        var kind: IncidentKind = .cpu
        var section = "overview", scan = "ready", confirm = "", toast = "", caps = "all", select = "", docker = ""
        var fda = true, inaccessible = 0, ssid = ""
        var bmPath: [String] = [], bmSelect: [[String]] = [], bmZoom: String?, bmP = 0.0, bmHover: String?
        var size = CGSize(width: 1400, height: 900)
        var lang = "en"
        /// Pixel scale of the PNG; 0 = the display's own (README screenshots use 2 on any display).
        var scale = 0.0
    }

    static func parse(_ args: [String]) -> Options {
        var o = Options(); var i = 0
        func next() -> String { i += 1; return i < args.count ? args[i] : "" }
        while i < args.count {
            switch args[i] {
            case "--snapshot": o.target = next()
            case "--out": o.out = next()
            case "--lang": o.lang = next()
            case "--scale": o.scale = Double(next()) ?? 0
            case "--dark": o.dark = true
            case "--incident": o.incident = true
            case "--kind": o.kind = IncidentKind(rawValue: next()) ?? .cpu
            case "--section": o.section = next()
            case "--scan": o.scan = next()
            case "--confirm": o.confirm = next()
            case "--toast": o.toast = next()
            case "--caps": o.caps = next()
            case "--select": o.select = next()
            case "--docker": o.docker = next()
            case "--fda": o.fda = next() != "none"
            case "--ssid": o.ssid = next()
            case "--inaccessible": o.inaccessible = Int(next()) ?? 0
            case "--bm-path": o.bmPath = next().split(separator: "/").map(String.init)
            case "--bm-select": o.bmSelect = next().split(separator: ",").map { $0.split(separator: "/").map(String.init) }
            case "--bm-zoom": o.bmZoom = next()
            case "--bm-p": o.bmP = Double(next()) ?? 0
            case "--bm-hover": o.bmHover = next()
            case "--size":
                let p = next().split(separator: "x").compactMap { Double($0) }
                if p.count == 2 { o.size = CGSize(width: p[0], height: p[1]) }
            default: break
            }
            i += 1
        }
        return o
    }

    static func run(_ args: [String]) -> Never {
        let o = parse(args)
        L10n.setLanguage(o.lang)
        NSApplication.shared.setActivationPolicy(.prohibited)
        let source = SampleSource(seed: 1, incident: o.incident, kind: o.kind)
        if o.docker == "down" { source.dockerRunning = false }
        source.diskFullAccess = o.fda; source.diskInaccessible = o.inaccessible
        if o.ssid == "needs" { source.ssidAccess = .needsPermission } else if o.ssid == "denied" { source.ssidAccess = .denied }
        if o.caps == "none" { source.capabilities = SourceCapabilities(docker: false, sensors: false, diskScan: false, netDetails: false) }
        let content = makeView(o, source)
        let root = NSHostingView(rootView: SnapshotBackdrop(dark: o.dark) { content })
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: o.size), styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: o.dark ? .darkAqua : .aqua)
        win.contentView = root
        root.frame = NSRect(origin: .zero, size: o.size)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        root.layoutSubtreeIfNeeded()
        let fixed = o.scale > 0 ? NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(o.size.width * o.scale), pixelsHigh: Int(o.size.height * o.scale),
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) : nil
        fixed?.size = root.bounds.size
        guard let rep = fixed ?? root.bitmapImageRepForCachingDisplay(in: root.bounds) else { fatalError("no bitmap") }
        root.cacheDisplay(in: root.bounds, to: rep)
        // If written with the display profile, colors shift in tools that ignore profiles; sRGB for comparison.
        let srgb = rep.converting(to: .sRGB, renderingIntent: .default) ?? rep
        guard let png = srgb.representation(using: .png, properties: [:]) else { fatalError("no png") }
        try? png.write(to: URL(fileURLWithPath: o.out))
        print("saved \(o.out)")
        exit(0)
    }

    /// Builds the view for the requested snapshot target.
    static func makeView(_ o: Options, _ source: SampleSource) -> AnyView {
        switch o.target {
        case "menubar":
            let model = StatusBlockLayout.model(source.snapshot, now: Date(), calendar: Fmt.calendar)
            return AnyView(MenubarStrip(model: model, highlighted: o.section == "open"))
        case "panel":
            return AnyView(VStack { HStack { Spacer(); PanelView(source: source) { _, _ in }.padding(.trailing, 140) }.padding(.top, 39); Spacer() })
        case "panels":
            // The README's panel pair: calm and during an incident, on one wallpaper, centered on each other.
            let busy = SampleSource(seed: 1, incident: true, kind: o.kind)
            return AnyView(HStack(alignment: .center, spacing: 56) {
                PanelView(source: source) { _, _ in }
                PanelView(source: busy) { _, _ in }
            }.frame(maxWidth: .infinity, maxHeight: .infinity))
        case "monitor":
            let state = MonitorState()
            state.go(MonitorSection(rawValue: o.section) ?? .overview)
            if !o.select.isEmpty { state.select(.cpu, o.select) }
            if o.confirm == "stop", let g = source.snapshot.groups.first(where: { $0.id == "next-web" }) { state.confirm = Actions.stop(g, force: true, source: source) }
            if o.confirm == "prune" { state.confirm = DockerActions.request(.pruneAnonymousVolumes, disk: source.snapshot.docker.disk, source: source) }
            if !o.toast.isEmpty { ToastCenter.shared.show(o.toast) }
            switch o.scan {
            case "none": source.diskScan = .none
            case "scanning": source.diskScan = .scanning(progress: 0.55, scannedGB: BubbleEngine.scannedTotal(source.diskTree, progress: 0.55), currentPath: "~/Library/Caches")
            default: source.diskScan = .ready(scannedAt: Date().addingTimeInterval(-18 * 60))
            }
            if o.section == "disk", o.confirm == "basket" {
                state.disk.path = ["Library"]
                state.disk.toggle(["Library", "Caches"], tree: source.diskTree)
                state.disk.toggle(["Library", "Developer"], tree: source.diskTree)
                state.disk.toggle(["Downloads", "Xcode_26.2.xip"], tree: source.diskTree)
            }
            return AnyView(MonitorView(source: source, state: state)
                .environment(\.bubbleStill, BubbleStill())
                .frame(width: o.size.width - 92, height: o.size.height - 96)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 40, y: 30)
                .padding(.top, 56))
        case "bubbles":
            // Map only, at a fixed size: --bm-path, --bm-select, --bm-zoom, --bm-p, --bm-hover
            let state = MonitorState()
            state.go(.disk)
            source.diskScan = o.scan == "scanning" ? .scanning(progress: 0.55, scannedGB: 128, currentPath: "~/Library/Caches") : .ready(scannedAt: Date())
            state.disk.path = o.bmPath
            for p in o.bmSelect { state.disk.toggle(p, tree: source.diskTree) }
            return AnyView(BubbleMapView(source: source, state: state)
                .environment(\.bubbleStill, BubbleStill(zoom: o.bmZoom, progress: o.bmP, hover: o.bmHover))
                .frame(width: o.size.width, height: o.size.height))
        case "charts":
            let cpu = source.series(.cpu, range: .m10), sys = source.series(.cpuSystem, range: .m10)
            let red = source.snapshot.incident != nil
            return AnyView(Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.t("cpu.chart.title")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                    AreaChart(series: [ChartSeries(cpu, color: red ? Theme.red : Theme.chart, fill: true, name: L10n.t("series.total")),
                                       ChartSeries(sys, color: Theme.chart2, name: L10n.t("series.system"))],
                              max: 100, height: 190, range: .m10, format: Fmt.pct, formatY: Fmt.pct)
                    Sparkline(Array(cpu.suffix(60)), color: red ? Theme.red : Theme.chart, height: 30, max: 100)
                }
            }.frame(width: 960).background(Theme.dyn(.init(white: 0.97, alpha: 1), .init(white: 0.12, alpha: 1))))
        case "social":
            // GitHub's social preview (--size 1280x640): icon, name and tagline beside the panel during an incident. The
            // icon is the README's, so run from the repository root.
            let icon = NSImage(contentsOfFile: ".github/assets/icon.png") ?? NSImage()
            let busy = SampleSource(seed: 1, incident: true, kind: o.kind)
            return AnyView(HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Image(nsImage: icon).resizable().frame(width: 176, height: 176).padding(.leading, -14)
                    Text(verbatim: "mystat").font(.system(size: 84, weight: .bold)).tracking(-1.5).padding(.top, 10)
                    Text(verbatim: "A calm system monitor\nfor the macOS menu bar.").font(.system(size: 36, weight: .medium))
                        .foregroundStyle(Theme.ink.opacity(0.78)).lineSpacing(4).padding(.top, 6)
                    Text(verbatim: "Free and open source · macOS 26+").font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Theme.ink.opacity(0.5)).padding(.top, 26)
                }
                .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                PanelView(source: busy) { _, _ in }.fixedSize().scaleEffect(0.71).frame(width: 250, height: 512)
            }
            .padding(.horizontal, 64)
            .frame(maxWidth: .infinity, maxHeight: .infinity))
        case "backdrop":
            // Wallpaper only: tools/readme-screenshots.py diffs against it to find a screenshot's content bounds.
            return AnyView(Color.clear)
        case "hero":
            // The README's first image (--size 1600x…): the menu bar with the mystat block, the panel opened beneath it and
            // the monitor beside it. 64 pt outer margins; the window is cut just below its first row of metrics and sits
            // level with the panel's bottom edge.
            let model = StatusBlockLayout.model(source.snapshot, now: Date(), calendar: Fmt.calendar)
            let blockWidth = ceil(StatusBlockLayout.width(model, measure: StatusBlockView.measure))
            let state = MonitorState()
            state.go(.overview)
            let margin: CGFloat = 64
            return AnyView(VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer()
                    BlockHost(model: model, highlighted: true).frame(width: blockWidth, height: 33)
                    Spacer().frame(width: margin)   // the block's right edge lines up with the panel's
                }
                .frame(height: 33)
                .background(o.dark ? Color.black.opacity(0.35) : Color.white.opacity(0.18))
                HStack(alignment: .bottom, spacing: 0) {
                    MonitorView(source: source, state: state)
                        .environment(\.bubbleStill, BubbleStill())
                        .frame(width: 1080, height: 645)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 40, y: 30)
                    Spacer()
                    PanelView(source: source) { _, _ in }
                }
                .padding(.horizontal, margin)
                .padding(.top, 6)
                Spacer()
            })
        default: return AnyView(Text(o.target).font(.largeTitle).foregroundStyle(Theme.ink))
        }
    }
}

/// Colorful wallpaper, so something shows behind the glass surfaces.
struct SnapshotBackdrop<Content: View>: View {
    let dark: Bool
    @ViewBuilder let content: () -> Content
    var body: some View {
        ZStack {
            if dark {
                LinearGradient(colors: [Color(red: 0.04, green: 0.05, blue: 0.08), Color(red: 0.08, green: 0.10, blue: 0.16)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(red: 0.49, green: 0.36, blue: 1).opacity(0.55), .clear], center: .init(x: 0.78, y: 0.2), startRadius: 0, endRadius: 520)
            } else {
                LinearGradient(colors: [Color(red: 0.13, green: 0.25, blue: 0.49), Color(red: 0.29, green: 0.37, blue: 0.69), Color(red: 0.60, green: 0.44, blue: 0.71)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color(red: 1, green: 0.66, blue: 0.43).opacity(0.95), .clear], center: .init(x: 0.12, y: 0.22), startRadius: 0, endRadius: 420)
                RadialGradient(colors: [Color(red: 0.93, green: 0.43, blue: 0.66).opacity(0.95), .clear], center: .init(x: 0.9, y: 0.12), startRadius: 0, endRadius: 380)
            }
            content()
        }
    }
}

/// Menu bar strip for snapshots: block on the right, 140 pt gap for system icons.
struct MenubarStrip: View {
    let model: StatusBlockModel
    let highlighted: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer()
                BlockHost(model: model, highlighted: highlighted)
                    .frame(width: ceil(StatusBlockLayout.width(model, measure: StatusBlockView.measure)), height: 33)
                Spacer().frame(width: 140)
            }
            .frame(height: 33)
            Spacer()
        }
    }
}

struct BlockHost: NSViewRepresentable {
    let model: StatusBlockModel
    let highlighted: Bool
    func makeNSView(context: Context) -> StatusBlockView {
        let v = StatusBlockView(model: model)
        v.appearance = NSAppearance(named: .darkAqua)   // light text over the colorful wallpaper
        v.highlighted = highlighted
        return v
    }
    func updateNSView(_ v: StatusBlockView, context: Context) { v.model = model; v.highlighted = highlighted }
}
