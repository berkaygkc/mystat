import AppKit
import MetalKit
import MystatCore
import Observation
import SwiftUI

/// Disk map: Metal glass bubbles + SwiftUI labels and selection buttons.
public struct BubbleMapView: View {
    private let source: any MetricsSource
    private let state: MonitorState
    @State private var model: BubbleMapModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.bubbleStill) private var still
    @Environment(\.displayScale) private var displayScale

    public init(source: some MetricsSource, state: MonitorState) {
        self.source = source
        self.state = state
        _model = State(initialValue: BubbleMapModel(source: source, state: state))
    }

    public var body: some View {
        let dark = scheme == .dark
        if let still {
            GeometryReader { g in
                let r = BubbleStillRender.make(source: source, disk: state.disk, size: g.size, scale: displayScale, dark: dark, cfg: still)
                ZStack(alignment: .topLeading) {
                    if let img = r.image { Image(decorative: img, scale: displayScale) }
                    // The same label images as the live layer.
                    ForEach(r.labels) { l in
                        let li = BubbleLabelImage.make(name: l.name, size: l.size, fontSize: l.fontSize, dark: dark, scale: displayScale)
                        Image(decorative: li.image, scale: displayScale)
                            .scaleEffect(l.scale).opacity(l.alpha).position(x: l.x, y: l.y)
                    }
                    BubbleOverlay(buttons: r.buttons, dark: dark) { _ in }
                }
            }
        } else {
            BubbleMetalHost(model: model, dark: dark)
        }
    }
}

/// Snapshot mode: a single frame instead of live Metal (`CAMetalLayer` is not captured in offscreen rendering).
public struct BubbleStill: Sendable, Equatable {
    public var time: Double
    public var mouse: CGPoint
    public var zoom: String?
    public var progress: Double
    public var hover: String?
    public init(time: Double = 2, mouse: CGPoint = CGPoint(x: 180, y: 60), zoom: String? = nil, progress: Double = 0, hover: String? = nil) {
        self.time = time; self.mouse = mouse; self.zoom = zoom; self.progress = progress; self.hover = hover
    }
}

extension EnvironmentValues {
    @Entry public var bubbleStill: BubbleStill? = nil
}

// MARK: - Layer content

struct BubbleLabel: Equatable, Identifiable {
    let id: String
    let name: String?
    let size: String
    let x: Double, y: Double
    let alpha: Double, fontSize: Double, scale: Double
}

struct BubbleButton: Equatable, Identifiable {
    let id: String
    let path: [String]
    let state: SelState
    let x: Double, y: Double, alpha: Double
    /// Protected folder: a lock instead of ＋, with the reason in the tooltip.
    var locked: String? = nil
}

/// Labels and ＋/✓ buttons derived from the bubbles in the frame.
/// Positions snap to `quantum` (one device pixel): the slow drift at rest causes only a few updates per second.
enum BubbleOverlayContent {
    private static func sstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t)
    }

    @MainActor
    static func make(_ f: BubbleFrame, engine e: BubbleEngine, width: Double, quantum q: Double) -> (labels: [BubbleLabel], buttons: [BubbleButton]) {
        func snap(_ v: Double, _ step: Double) -> Double { (v / step).rounded() * step }
        var labels: [BubbleLabel] = []
        var seen = Set<String>()
        for m in f.mains where m.alpha >= 0.05 && m.r >= 17 {
            guard seen.insert(m.item.id).inserted, let t = e.labelText(for: m.item, radius: m.r) else { continue }
            let size = e.scanProgress.map { Fmt.size(m.item.size * BubbleEngine.scanGrowth(phase: m.item.phase, progress: $0)) } ?? t.size
            labels.append(BubbleLabel(id: m.item.id, name: t.name, size: size, x: snap(m.x, q), y: snap(m.y, q),
                                      alpha: snap(m.alpha * sstep(17, 30, m.r) * (m.r > width ? 0 : 1), 0.005),
                                      fontSize: snap(max(11, min(19, m.r / 5.2)), 0.1), scale: snap(1 + 0.035 * m.hover, 0.001)))
        }
        var buttons: [BubbleButton] = []
        if !e.isAnimating {
            let ang = -Double.pi / 4
            for m in f.mains where m.item.kind != .other && m.r >= 20 && m.alpha >= 0.6 {
                let st: SelState = m.selection >= 1 ? .selected : m.selection > 0 ? .implied : .none
                if st == .none && m.hover < 0.3 { continue }
                let path = e.path + [m.item.name]
                buttons.append(BubbleButton(id: m.item.id, path: path, state: st,
                                            x: snap(m.x + cos(ang) * m.r * 0.84, q), y: snap(m.y + sin(ang) * m.r * 0.84, q),
                                            alpha: snap(st == .none ? min(1, m.hover * 1.4) : 1, 0.01),
                                            locked: DeletionGuard.reason(path: path)))
            }
        }
        return (labels, buttons)
    }
}

/// Static frame: stands in for the live render sequence at t = 2.0 s.
enum BubbleStillRender {
    @MainActor
    static func make(source: any MetricsSource, disk: DiskUIState, size: CGSize, scale: CGFloat, dark: Bool, cfg: BubbleStill)
        -> (image: CGImage?, labels: [BubbleLabel], buttons: [BubbleButton]) {
        guard size.width > 50, size.height > 50 else { return (nil, [], []) }
        let e = BubbleEngine(tree: source.diskTree, path: disk.path, viewSize: size)
        if source.diskScanSimulated, case .scanning(let p, _, _) = source.diskScan { e.scanProgress = p }
        let sel: ([String]) -> SelState = { disk.basket.state(of: $0) }
        var t = cfg.time
        if cfg.hover != nil { for i in 0..<60 { _ = e.frame(at: t - 1 + Double(i) / 60, hover: cfg.hover, selection: sel) } }
        var f = e.frame(at: t, hover: cfg.hover, selection: sel)
        if let z = cfg.zoom, e.zoomIn(z, at: t) {
            _ = e.frame(at: t, hover: nil, selection: sel)
            t += 1.4 * cfg.progress
            f = e.frame(at: t, hover: nil, selection: sel)
        }
        let o = BubbleOverlayContent.make(f, engine: e, width: size.width, quantum: 1 / scale)
        guard let dev = MTLCreateSystemDefaultDevice(), let r = BubbleRenderer(device: dev) else { return (nil, o.labels, o.buttons) }
        r.isDark = dark
        r.mouse = cfg.mouse
        return (r.renderToImage(frame: f, size: size, scale: scale, time: t), o.labels, o.buttons)
    }
}

// MARK: - Live model

/// Advances the engine on the renderer clock; carries path, deletion and scan state to the map; interprets mouse and keys.
@MainActor @Observable
final class BubbleMapModel {
    /// Labels do not go through SwiftUI (updated per frame); the layer reads them from here every frame.
    @ObservationIgnored private(set) var labels: [BubbleLabel] = []
    private(set) var buttons: [BubbleButton] = []
    /// The screen's pixel ratio; label positions snap to this step.
    @ObservationIgnored var pixelScale = 2.0

    @ObservationIgnored private let source: any MetricsSource
    @ObservationIgnored private let state: MonitorState
    @ObservationIgnored private var engine: BubbleEngine?
    @ObservationIgnored private var hover: String?
    @ObservationIgnored private var token: Int
    @ObservationIgnored private var lastFrame: BubbleFrame?
    @ObservationIgnored private var shownProgress: Double?
    /// Real scan: re-layout as the tree grows (at most every 2 s, so navigation stays free in between).
    @ObservationIgnored private var lastScannedGB: Double?
    @ObservationIgnored private var lastGrowth = -Double.infinity
    static let growthInterval = 2.0

    init(source: some MetricsSource, state: MonitorState) {
        self.source = source
        self.state = state
        token = state.disk.relayoutToken
    }

    private var disk: DiskUIState { state.disk }

    func frame(at t: Double, size: CGSize) -> BubbleFrame? {
        guard size.width > 50, size.height > 50 else { return nil }
        let e: BubbleEngine
        let tree = source.diskTree
        if let x = engine, x.tree === tree {
            e = x; e.resize(size)
        } else {   // the tree changed (scan started, loaded from cache): the closest folder that exists in the new tree
            var p = disk.path
            let loading = tree.scanIndex == nil && tree.root.children == nil   // placeholder: the path is kept
            while !loading, !p.isEmpty, tree.node(at: p) == nil { p.removeLast() }
            if p != disk.path { disk.path = p }
            e = BubbleEngine(tree: tree, path: p, viewSize: size); engine = e
            hover = nil; lastScannedGB = nil
        }
        sync(e, at: t)
        if !source.diskScanSimulated { growLive(e, at: t) }
        // Sample scan: progress jumps every 100 ms; it is tracked so bubbles grow smoothly, and eases to 1 when done.
        if source.diskScanSimulated, case .scanning(let p, _, _) = source.diskScan {
            shownProgress = shownProgress.map { $0 + (p - $0) * 0.1 } ?? 0
        } else if let s = shownProgress {
            shownProgress = s > 0.998 ? nil : s + (1 - s) * 0.1
        }
        e.scanProgress = shownProgress
        let basket = disk.basket
        let f = e.frame(at: t, hover: hover ?? disk.hoverName, selection: { basket.state(of: $0) })
        lastFrame = f
        if disk.isMapAnimating != e.isAnimating { disk.isMapAnimating = e.isAnimating }
        let o = BubbleOverlayContent.make(f, engine: e, width: size.width, quantum: 1 / pixelScale)
        labels = o.labels
        if o.buttons != buttons { buttons = o.buttons }
        return f
    }

    /// Real scan: the source updates the tree once a second; the map re-lays out at most every `growthInterval`,
    /// and once more when the scan finishes.
    private func growLive(_ e: BubbleEngine, at t: Double) {
        let gb: Double? = if case .scanning(_, let g, _) = source.diskScan { g } else { nil }
        if let gb {
            guard gb != lastScannedGB, t - lastGrowth >= Self.growthInterval else { return }
            lastScannedGB = gb; lastGrowth = t
            e.relayout(at: t)
        } else if lastScannedGB != nil {   // finished or stopped
            lastScannedGB = nil
            e.relayout(at: t)
        }
    }

    /// Applies path changes (map, path row, sidebar list, Esc) with animation. While a transition runs,
    /// `DiskUIState.open` already rejects new navigation; a path that still arrives is applied when the transition ends.
    private func sync(_ e: BubbleEngine, at t: Double) {
        if disk.relayoutToken != token {
            token = disk.relayoutToken
            // If the current folder was deleted, jump out of it; otherwise re-layout (the engine defers it if a transition is running).
            if source.diskTree.node(at: e.path) == nil { e.setPath(disk.path) } else { e.relayout(at: t) }
            hover = nil
        }
        guard !e.isAnimating, disk.path != e.path else { return }
        let cur = e.path, p = disk.path
        if p.count == cur.count + 1, Array(p.dropLast()) == cur {
            if !e.zoomIn(p[p.count - 1], at: t) { e.setPath(p) }
        } else if p.count < cur.count, Array(cur.prefix(p.count)) == p {
            e.zoomOut(to: p, at: t)
        } else {
            e.setPath(p)
        }
        hover = nil
    }

    /// Pointer; the return value says whether to show the pointing-hand cursor.
    func mouseMoved(_ p: CGPoint) -> Bool {
        guard let e = engine, !e.isAnimating else { hover = nil; return false }
        let hit = e.hitTest(p, current: hover)
        hover = hit?.name
        return hit.map { $0.kind != .other } ?? false
    }

    func mouseExited() { hover = nil }

    /// So no navigation lock remains when the map leaves the screen.
    func detach() { disk.isMapAnimating = false }

    /// Clicking a folder enters it; clicking a file, or ⌘-click, selects.
    func click(_ p: CGPoint, flags: NSEvent.ModifierFlags) {
        guard let e = engine, !e.isAnimating, let h = hover,
              let m = lastFrame?.mains.first(where: { $0.item.name == h }), m.item.kind != .other,
              hypot(p.x - m.x, p.y - m.y) <= m.r else { return }
        let path = e.path + [h]
        if flags.contains(.command) || flags.contains(.control) || !m.item.hasChildren { toggle(path) } else { disk.open(path) }
    }

    func toggle(_ path: [String]) { disk.toggle(path, tree: source.diskTree) }

    /// Esc: up one level · Space: select the bubble under the pointer · ⌫: bulk delete confirmation.
    func key(_ ev: NSEvent) -> Bool {
        guard ev.modifierFlags.intersection([.command, .control, .option]).isEmpty, state.confirm == nil, state.section == .disk else { return false }
        switch ev.keyCode {
        case 53:
            guard !disk.path.isEmpty else { return false }
            disk.open(Array(disk.path.dropLast()))
        case 49:
            guard let h = hover, let e = engine else { return false }
            toggle(e.path + [h])
        case 51, 117:
            guard let req = disk.confirmDelete(tree: source.diskTree, source: source) else { return false }
            state.confirm = req
        default:
            return false
        }
        return true
    }
}

// MARK: - Metal view

struct BubbleMetalHost: NSViewRepresentable {
    let model: BubbleMapModel
    let dark: Bool

    func makeCoordinator() -> BubbleRenderer? {
        MTLCreateSystemDefaultDevice().flatMap { BubbleRenderer(device: $0) }
    }

    func makeNSView(context: Context) -> BubbleMapContainer {
        BubbleMapContainer(model: model, renderer: context.coordinator, dark: dark)
    }

    func updateNSView(_ v: BubbleMapContainer, context: Context) { v.setDark(dark) }

    static func dismantleNSView(_ v: BubbleMapContainer, coordinator: BubbleRenderer?) {
        v.teardown()
        coordinator?.frameProvider = nil
    }
}

/// Three layers: `MTKView` (bubbles), CA labels, SwiftUI ＋/✓ buttons. The buttons live in a separate `NSHostingView`
/// that does not report its size, so changes do not trigger a recalculation of the monitor window's SwiftUI layout.
final class BubbleMapContainer: NSView {
    let metal: BubbleMTKView
    private let labels = BubbleLabelsView()
    private let overlay: NSHostingView<BubbleLiveOverlay>
    private let model: BubbleMapModel
    private weak var renderer: BubbleRenderer?
    private var dark: Bool

    init(model: BubbleMapModel, renderer: BubbleRenderer?, dark: Bool) {
        self.model = model
        self.renderer = renderer
        self.dark = dark
        metal = BubbleMTKView(frame: .zero, device: renderer?.device)
        overlay = NSHostingView(rootView: BubbleLiveOverlay(model: model, dark: dark))
        overlay.sizingOptions = []
        super.init(frame: .zero)
        addSubview(metal)
        addSubview(labels)
        addSubview(overlay)
        guard let r = renderer else { return }
        metal.colorPixelFormat = BubbleRenderer.pixelFormat
        metal.framebufferOnly = true
        metal.preferredFramesPerSecond = 60
        metal.presentsWithTransaction = true
        metal.autoResizeDrawable = true
        if let layer = metal.layer as? CAMetalLayer {
            layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)   // the same color space as a browser canvas
            layer.isOpaque = true
        }
        metal.delegate = r
        r.isDark = dark
        r.frameProvider = { [weak self] t in
            guard let self, let f = model.frame(at: t, size: metal.bounds.size) else { return nil }
            labels.update(model.labels, dark: self.dark)
            return f
        }
        metal.onMove = { [weak r] p in r?.mouse = p; return model.mouseMoved(p) }
        metal.onExit = { [weak r] in r?.mouse = nil; model.mouseExited() }
        metal.onClick = { p, flags in model.click(p, flags: flags) }
        metal.onKey = { model.key($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        metal.frame = bounds
        labels.frame = bounds
        overlay.frame = bounds
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        model.pixelScale = Double(window?.backingScaleFactor ?? 2)
    }

    func setDark(_ dark: Bool) {
        self.dark = dark
        renderer?.isDark = dark
        if overlay.rootView.dark != dark { overlay.rootView = BubbleLiveOverlay(model: model, dark: dark) }
    }

    /// Mouse events go to the map; only the area over the ＋/✓ buttons goes to the overlay.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        guard bounds.contains(p) else { return nil }
        let q = CGPoint(x: p.x, y: isFlipped ? p.y : bounds.height - p.y)
        if model.buttons.contains(where: { $0.alpha > 0.05 && hypot($0.x - q.x, $0.y - q.y) <= 14 }) {
            return overlay.hitTest(p) ?? metal   // the subview's hitTest point is in the superview's (this view's) coordinates
        }
        return metal
    }

    func teardown() {
        metal.isPaused = true
        metal.teardown()
        model.detach()
    }
}

/// An `MTKView` that forwards mouse, key and visibility events to the model.
final class BubbleMTKView: MTKView {
    var onMove: ((CGPoint) -> Bool)?
    var onExit: (() -> Void)?
    var onClick: ((CGPoint, NSEvent.ModifierFlags) -> Void)?
    var onKey: ((NSEvent) -> Bool)?
    private var tracking: NSTrackingArea?
    private var keyMonitor: Any?
    private var occlusion: NSObjectProtocol?
    private var downAt: CGPoint?

    // The window can be dragged from its background; map clicks must not move the window.
    override var mouseDownCanMoveWindow: Bool { false }

    private func local(_ e: NSEvent) -> CGPoint {
        let p = convert(e.locationInWindow, from: nil)
        return CGPoint(x: p.x, y: bounds.height - p.y)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseMoved(with e: NSEvent) {
        (onMove?(local(e)) == true ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    override func mouseExited(with e: NSEvent) {
        onExit?()
        NSCursor.arrow.set()
    }

    override func mouseDown(with e: NSEvent) { downAt = local(e) }

    override func mouseUp(with e: NSEvent) {
        let p = local(e)
        defer { downAt = nil }
        guard let d = downAt, hypot(p.x - d.x, p.y - d.y) < 5 else { return }
        onClick?(p, e.modifierFlags)
    }

    /// Draws only while visible: stops when the window closes, is minimized, or is fully covered.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        teardown()
        guard let w = window else { isPaused = true; return }
        isPaused = !w.occlusionState.contains(.visible)
        occlusion = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let w = self.window else { return }
                self.isPaused = !w.occlusionState.contains(.visible)
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.window, self.onKey?(e) == true else { return e }
            return nil
        }
    }

    func teardown() {
        if let occlusion { NotificationCenter.default.removeObserver(occlusion) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        occlusion = nil
        keyMonitor = nil
    }
}

// MARK: - Selection buttons

/// Redrawn only when the buttons change.
struct BubbleLiveOverlay: View {
    let model: BubbleMapModel
    let dark: Bool
    var body: some View {
        BubbleOverlay(buttons: model.buttons, dark: dark) { model.toggle($0) }
    }
}

struct BubbleOverlay: View {
    let buttons: [BubbleButton]
    let dark: Bool
    let onToggle: ([String]) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(buttons) { b in
                BubbleSelectButton(button: b, dark: dark) { if b.state != .implied { onToggle(b.path) } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Selection button: a 26 pt glass circle; ＋ / blue ✓ / faded blue ✓ (selected via parent folder) / lock (protected folder; clicking
/// reports the reason as a toast).
private struct BubbleSelectButton: View {
    let button: BubbleButton
    let dark: Bool
    let action: () -> Void
    @State private var hovering = false

    private var fill: Color {
        switch button.state {
        case .selected: Theme.acc
        case .implied: dark ? Color(red: 10 / 255, green: 132 / 255, blue: 1).opacity(0.22) : Theme.accSoft
        case .none: dark ? Color(red: 60 / 255, green: 60 / 255, blue: 70 / 255).opacity(0.62) : .white.opacity(0.66)
        }
    }
    private var tint: Color { button.state == .selected ? .white : button.state == .implied ? Theme.acc : Theme.ink }
    private var shadow: Color {
        button.state == .selected ? (dark ? Color(red: 10 / 255, green: 132 / 255, blue: 1).opacity(0.4) : Color(red: 0, green: 113 / 255, blue: 227 / 255).opacity(0.35))
            : button.state == .none ? (dark ? .black.opacity(0.4) : Color(red: 20 / 255, green: 20 / 255, blue: 60 / 255).opacity(0.18)) : .clear
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: button.locked != nil ? "lock.fill" : button.state == .none ? "plus" : "checkmark")
                .font(.system(size: button.locked != nil ? 10 : 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background {
                    ZStack {
                        Circle().fill(fill)
                        if button.state == .none {
                            Circle().strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.2 : 0.95), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.18)), lineWidth: 1)
                        }
                        Circle().strokeBorder(.black.opacity(button.state == .none ? (dark ? 0.5 : 0.12) : button.state == .selected ? (dark ? 0.4 : 0.1) : 0), lineWidth: 0.5)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(button.state == .none ? .regular : .identity, in: Circle())
        .shadow(color: shadow, radius: 6, y: 4)
        .brightness(hovering && button.state != .implied ? 0.04 : 0)
        .onHover { hovering = $0 }
        .help(button.locked ?? L10n.t(button.state == .selected ? "disk.help.deselect" : button.state == .implied ? "disk.help.implied" : "disk.help.select"))
        .opacity(button.alpha)
        .position(x: button.x, y: button.y)
    }
}
