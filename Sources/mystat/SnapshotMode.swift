import AppKit
import MystatCore
import MystatUI
import SwiftUI

/// `mystat --snapshot <menubar|panel|monitor|bubbles|charts> --out x.png [--lang en|tr] [--dark] [--incident] [--kind k] [--section s] [--size WxH] [--scan s]`
/// Görünümü ekran dışı bir pencerede çizip PNG'ye yazar; mockup karşılaştırması içindir.
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
    }

    static func parse(_ args: [String]) -> Options {
        var o = Options(); var i = 0
        func next() -> String { i += 1; return i < args.count ? args[i] : "" }
        while i < args.count {
            switch args[i] {
            case "--snapshot": o.target = next()
            case "--out": o.out = next()
            case "--lang": o.lang = next()
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
        guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { fatalError("bitmap yok") }
        root.cacheDisplay(in: root.bounds, to: rep)
        // Ekran profiliyle yazılırsa profil okumayan araçlarda renkler kayıyor; karşılaştırma için sRGB.
        let srgb = rep.converting(to: .sRGB, renderingIntent: .default) ?? rep
        guard let png = srgb.representation(using: .png, properties: [:]) else { fatalError("png yok") }
        try? png.write(to: URL(fileURLWithPath: o.out))
        print("saved \(o.out)")
        exit(0)
    }

    /// Hedefler sonraki tasklarda eklenir.
    static func makeView(_ o: Options, _ source: SampleSource) -> AnyView {
        switch o.target {
        case "menubar":
            let model = StatusBlockLayout.model(source.snapshot, now: Date(), calendar: Fmt.calendar)
            return AnyView(MenubarStrip(model: model, highlighted: o.section == "open"))
        case "panel":
            return AnyView(VStack { HStack { Spacer(); PanelView(source: source) { _, _ in }.padding(.trailing, 140) }.padding(.top, 39); Spacer() })
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
            // Yalnızca harita, mockup karesiyle aynı boyutta: --bm-path, --bm-select, --bm-zoom, --bm-p, --bm-hover
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
                    Text("Kullanım").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                    AreaChart(series: [ChartSeries(cpu, color: red ? Theme.red : Theme.chart, fill: true, name: "toplam"),
                                       ChartSeries(sys, color: Theme.chart2, name: "sistem")],
                              max: 100, height: 190, range: .m10, format: Fmt.pct, formatY: Fmt.pct)
                    Sparkline(Array(cpu.suffix(60)), color: red ? Theme.red : Theme.chart, height: 30, max: 100)
                }
            }.frame(width: 960).background(Theme.dyn(.init(white: 0.97, alpha: 1), .init(white: 0.12, alpha: 1))))
        default: return AnyView(Text(o.target).font(.largeTitle).foregroundStyle(Theme.ink))
        }
    }
}

/// Mockup'taki renkli duvar kâğıdı; cam yüzeylerin arkasında bir şey görünsün diye.
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

/// Anlık görüntü için menü çubuğu şeridi: blok sağda, sistem simgeleri için 140 pt boşluk.
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
        v.appearance = NSAppearance(named: .darkAqua)   // renkli duvar kâğıdı üzerinde açık metin
        v.highlighted = highlighted
        return v
    }
    func updateNSView(_ v: StatusBlockView, context: Context) { v.model = model; v.highlighted = highlighted }
}
