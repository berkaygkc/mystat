import CoreGraphics
import Foundation

public struct BubbleItem: Sendable {
    public let id: String          // yol, "a/b"
    public let name: String
    public let kind: NodeKind
    public let size: Double
    public let phase: Double
    public var x: Double, y: Double, r: Double
    public var kids: [PackCircle]
    public let hasChildren: Bool
}

public struct MainBubble: Sendable {
    public let item: BubbleItem
    public let x: Double, y: Double, r: Double
    public let alpha: Double, hover: Double, amp: Double
    /// 0 yok, 0,5 üst klasörle seçili, 1 seçili.
    public let selection: Double
}

public struct Droplet: Sendable { public let x: Double, y: Double, r: Double, alpha: Double }

public struct Membrane: Sendable {
    public let x: Double, y: Double, r: Double
    public let body: Double, rim: Double, phase: Double, amp: Double
    public let kind: NodeKind
}

public struct Ripple: Sendable { public let x: Double, y: Double, age: Double, amp: Double }

public struct BgTint: Sendable {
    public var kind: NodeKind?
    public var amount: Double
}

public struct BubbleFrame: Sendable {
    public let mains: [MainBubble]
    public let droplets: [Droplet]
    public let membrane: Membrane?
    public let ripple: Ripple?
    public let zoomLog: Double
    /// Arka planın girilen klasör türüne göre renklenmesi; `from`→`to` arası `t`.
    public let bgFrom: BgTint, bgTo: BgTint, bgT: Double
}

/// Disk haritasının çizimden bağımsız durum makinesi (mockup'taki `BubbleMap`): yerleşim, süzülme,
/// hover itmesi, içine girme/çıkma kamerası, zar, dalga, silme sonrası yeniden yerleşim.
@MainActor
public final class BubbleEngine {
    public private(set) var path: [String]
    public private(set) var items: [BubbleItem] = []
    public var isAnimating: Bool { anim != nil }
    /// Tarama sürerken 0…1: balonlar yerinde büyür (spec §6.4). `nil` = tarama yok.
    public var scanProgress: Double?

    private let tree: DiskTree
    private var size: CGSize
    private var R0 = 0.0
    private var C = CGPoint.zero
    private var anim: Anim?
    private var arrive = -10.0
    private var zoomLog = 0.0
    private var bg = BgTint(kind: nil, amount: 0)
    private var rip: (x: Double, y: Double, t0: Double, amp: Double)?
    private var off: [String: CGPoint] = [:]
    private var hovW: [String: Double] = [:]
    private var pendingRelayout = false
    private var outTarget: [String]?
    private var lastMains: [MainBubble] = []

    private enum Kind { case zoomIn, zoomOut, relayout }
    private struct Anim {
        let kind: Kind
        let t0: Double, dur: Double
        var B: BubbleItem?
        var sib: [BubbleItem] = []
        var next: [BubbleItem] = []
        var mapped: [BubbleItem] = []
        var targetPath: [String] = []
        var z0 = 0.0, zs = 0.0
        var tint0 = BgTint(kind: nil, amount: 0), tint1 = BgTint(kind: nil, amount: 0)
        var ripDone = false
        var pairs: [(from: BubbleItem, to: BubbleItem)] = []
        var gone: [BubbleItem] = []
    }

    public init(tree: DiskTree, path: [String], viewSize: CGSize) {
        self.tree = tree
        self.size = viewSize
        self.path = path
        computeGeometry()
        items = layout(path)
        bg = tint(for: path)
    }

    // MARK: - Geometri ve yerleşim

    private func computeGeometry() {
        R0 = min(size.width, size.height - 46) / 2 - 22
        C = CGPoint(x: size.width / 2, y: (size.height - 46) / 2 + 8)
    }

    public func resize(_ s: CGSize) {
        guard s != size else { return }
        size = s
        computeGeometry()
        anim = nil
        items = layout(path)
    }

    /// Taramanın `progress` anında bir balonun ulaştığı boyut oranı; evreye göre farklı hızda, sonunda 1.
    public static func scanGrowth(phase: Double, progress: Double) -> Double {
        min(1, max(0.04, progress * 1.3 - phase * 0.3))
    }

    /// Tarama sürerken bir öğenin o ana kadar biriken boyutu (haritadaki balonla aynı büyüme); tarama yoksa kendisi.
    public static func scannedSize(_ size: Double, path: [String], progress: Double?) -> Double {
        guard let p = progress else { return size }
        return size * scanGrowth(phase: hash01(path.joined(separator: "/")), progress: p)
    }

    /// Taramanın o ana kadar ev klasöründe biriktirdiği toplam (kökteki satırların toplamı).
    @MainActor
    public static func scannedTotal(_ tree: DiskTree, progress: Double) -> Double {
        (tree.root.children ?? []).reduce(0) { $0 + scannedSize($1.size, path: [$1.name], progress: progress) }
    }

    public static let maxBubbles = 24
    static let previewKids = 12

    /// Önizleme damlacıkları için bir balonun en büyük çocukları; kalanlar toplamı bozulmasın diye tek parça.
    static func preview(_ sorted: [DiskNode]) -> [DiskNode] {
        guard sorted.count > previewKids else { return sorted }
        let head = Array(sorted.prefix(previewKids - 1))
        return head + [DiskNode("", sorted.dropFirst(previewKids - 1).reduce(0) { $0 + $1.size })]
    }

    /// Mockup'taki `hash01`: FNV-1a, 1000'e göre.
    static func hash01(_ s: String) -> Double {
        var h: UInt32 = 2_166_136_261
        for u in s.utf16 { h ^= UInt32(u); h = h &* 16_777_619 }
        return Double(h % 1000) / 1000
    }

    private func layout(_ p: [String]) -> [BubbleItem] {
        guard let node = tree.node(at: p), var children = node.children else { return [] }
        // Shader seviye başına en fazla 24 ana balon çizer: en büyük 23'ü ayrı, kalanlar tek bir "Diğer" balonu.
        var rest: DiskNode?
        if children.count > Self.maxBubbles {
            let sorted = children.sorted { $0.size > $1.size }
            children = Array(sorted.prefix(Self.maxBubbles - 1))
            rest = DiskNode("Diğer", sorted.dropFirst(Self.maxBubbles - 1).reduce(0) { $0 + $1.size }, ref: .other(count: sorted.count - children.count))
            children.append(rest!)
        }
        let kids = children.map { c -> (DiskNode, [DiskNode]) in
            if c !== rest { _ = tree.node(at: p + [c.name]) }   // önizleme için bir seviye öte üretilsin
            return (c, Self.preview((c.children ?? []).sorted { $0.size > $1.size }))
        }
        .map { c, g -> (DiskNode, [DiskNode], Double) in (c, g, g.isEmpty ? c.size : g.reduce(0) { $0 + $1.size }) }
        .sorted { $0.2 > $1.2 }
        let packed = CirclePack.layout(children: kids.map { PackInput(value: $0.2, grandchildren: $0.1.map(\.size)) },
                                       size: 2 * R0, rootPadding: 13, childPadding: 4)
        let ox = Double(C.x) - R0, oy = Double(C.y) - R0
        return zip(kids, packed).map { k, pc in
            let id = (p + [k.0 === rest ? "…diğer" : k.0.name]).joined(separator: "/")
            return BubbleItem(id: id, name: k.0.name, kind: k.0.kind, size: k.0.size, phase: Self.hash01(id),
                              x: pc.0.x + ox, y: pc.0.y + oy, r: pc.0.r,
                              kids: pc.1.prefix(5).map { PackCircle(x: $0.x + ox, y: $0.y + oy, r: $0.r) },
                              hasChildren: k.0.canHaveChildren)
        }
    }

    private func tint(for p: [String]) -> BgTint {
        guard !p.isEmpty, let n = tree.node(at: p) else { return BgTint(kind: nil, amount: 0) }
        return BgTint(kind: n.kind, amount: 1)
    }

    private func mapInto(_ list: [BubbleItem], _ B: BubbleItem) -> [BubbleItem] {
        let k = B.r / R0, cx = Double(C.x), cy = Double(C.y)
        return list.map { it in
            var m = it
            m.x = B.x + (it.x - cx) * k; m.y = B.y + (it.y - cy) * k; m.r = it.r * k
            m.kids = it.kids.map { PackCircle(x: B.x + ($0.x - cx) * k, y: B.y + ($0.y - cy) * k, r: $0.r * k) }
            return m
        }
    }

    // MARK: - Gezinme

    @discardableResult
    public func zoomIn(_ name: String, at t: Double) -> Bool {
        guard anim == nil, let B = items.first(where: { $0.name == name }), B.hasChildren else { return false }
        let npath = path + [name]
        let next = layout(npath)
        guard !next.isEmpty else { return false }
        anim = Anim(kind: .zoomIn, t0: t, dur: 1.4, B: B, sib: items.filter { $0.id != B.id }, next: next, mapped: mapInto(next, B),
                    targetPath: npath, z0: zoomLog, zs: log2(R0 / B.r), tint0: bg, tint1: tint(for: npath))
        return true
    }

    public func zoomOut(to target: [String], at t: Double) {
        guard anim == nil, path.count > target.count else { return }
        outTarget = target
        startZoomOut(at: t)
    }

    private func startZoomOut(at t: Double) {
        guard let target = outTarget, path.count > target.count else { outTarget = nil; return }
        let ppath = Array(path.dropLast())
        let prev = layout(ppath)
        guard let B = prev.first(where: { $0.name == path.last }) else { setPath(ppath); outTarget = nil; return }
        anim = Anim(kind: .zoomOut, t0: t, dur: path.count - target.count > 1 ? 0.8 : 1.25, B: B, sib: prev.filter { $0.id != B.id },
                    next: prev, mapped: mapInto(items, B), targetPath: ppath, z0: zoomLog, zs: log2(R0 / B.r), tint0: bg, tint1: tint(for: ppath))
    }

    /// Animasyonsuz konum değişikliği (ilgisiz bir yola atlama).
    public func setPath(_ p: [String]) {
        anim = nil
        path = p
        items = layout(p)
        bg = tint(for: p)
        off.removeAll(); hovW.removeAll()
    }

    /// Silme sonrası; animasyon sürüyorsa bitince uygulanır (Review Focus #4).
    public func relayout(at t: Double) {
        guard anim == nil else { pendingRelayout = true; return }
        let next = layout(path)
        let byID = Dictionary(next.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var pairs: [(BubbleItem, BubbleItem)] = []
        var gone: [BubbleItem] = []
        for it in items { if let to = byID[it.id] { pairs.append((it, to)) } else { gone.append(it) } }
        for it in next where !items.contains(where: { $0.id == it.id }) { var from = it; from.r = 0.5; pairs.append((from, it)) }
        anim = Anim(kind: .relayout, t0: t, dur: 1.0, next: next, pairs: pairs.map { (from: $0.0, to: $0.1) }, gone: gone)
        if let big = gone.max(by: { $0.r < $1.r }) { rip = (big.x, big.y, t, 0.8) }
    }

    // MARK: - Kare

    private static func sstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t)
    }
    private static func easeIO(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    private static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    private func drift(_ it: BubbleItem, _ t: Double) -> CGPoint {
        let A = min(4.5, it.r * 0.035), ph = it.phase
        return CGPoint(x: A * (sin(t * 0.37 + ph * 6.28) + 0.5 * sin(t * 0.61 + ph * 12.1)),
                       y: A * (cos(t * 0.29 + ph * 9.1) + 0.5 * sin(t * 0.53 + ph * 4.7)))
    }

    public func frame(at t: Double, hover: String?, selection: ([String]) -> SelState) -> BubbleFrame {
        var mains: [MainBubble] = [], drops: [Droplet] = []
        var membrane: Membrane?
        var cam = (cx: Double(C.x), cy: Double(C.y), s: 1.0)
        let boost = 1 + 1.4 * exp(-(t - arrive) * 2.4)
        var bgFrom = bg, bgTo = bg, bgT = 0.0
        let atRest = anim == nil

        func S(_ x: Double, _ y: Double) -> (Double, Double) { ((x - cam.cx) * cam.s + Double(C.x), (y - cam.cy) * cam.s + Double(C.y)) }
        func add(_ it: BubbleItem, _ a: Double, _ pa: Double, hov: Double = 0, ampMul: Double = 1, fly: (x: Double, y: Double, k: Double)? = nil) {
            let dr = drift(it, t)
            var o = off[it.id] ?? .zero
            if let f = fly { o.x += (it.x - f.x) * f.k; o.y += (it.y - f.y) * f.k }
            let (sx, sy) = S(it.x + dr.x + o.x, it.y + dr.y + o.y)
            let k = scanProgress.map { sqrt(Self.scanGrowth(phase: it.phase, progress: $0)) } ?? 1
            let sel: Double
            if atRest, items.contains(where: { $0.id == it.id }) {
                switch selection(it.id.split(separator: "/").map(String.init)) { case .selected: sel = 1; case .implied: sel = 0.5; case .none: sel = 0 }
            } else { sel = 0 }
            mains.append(MainBubble(item: it, x: sx, y: sy, r: it.r * cam.s * k, alpha: a * (it.kind == .other ? 0.8 : 1), hover: hov,
                                    amp: 0.018 * boost * (1 + 0.6 * hov) * ampMul, selection: sel))
            if pa > 0.004 {
                for g in it.kids {
                    let (gx, gy) = S(g.x + dr.x + o.x, g.y + dr.y + o.y)
                    drops.append(Droplet(x: sx + (gx - sx) * k, y: sy + (gy - sy) * k, r: g.r * cam.s * k, alpha: pa))
                }
            }
        }

        if let A = anim {
            let p = min(1, (t - A.t0) / A.dur)
            switch A.kind {
            case .zoomIn:
                let B = A.B!
                let ez = Self.easeIO(p), ep = Self.easeOut(min(1, p * 1.15))
                let s = pow(2, A.zs * ez)
                let sbx = Self.lerp(B.x, Double(C.x), ep), sby = Self.lerp(B.y, Double(C.y), ep)
                cam = (B.x - (sbx - Double(C.x)) / s, B.y - (sby - Double(C.y)) / s, s)
                for it in A.sib { add(it, 1 - Self.sstep(0.02, 0.5, p), 0.5 * (1 - Self.sstep(0, 0.35, p)), fly: (B.x, B.y, 0.9 * ez)) }
                for it in A.mapped { add(it, Self.sstep(0.22, 0.72, p), 0.5 * Self.sstep(0.62, 1, p), ampMul: 1 + 1.2 * Self.sstep(0.4, 0.9, p)) }
                let (bx, by) = S(B.x, B.y)
                membrane = Membrane(x: bx, y: by, r: B.r * s * (1 + 2.4 * pow(Self.sstep(0.28, 1, p), 1.6)),
                                    body: 1 - Self.sstep(0.3, 0.75, p), rim: 1 - Self.sstep(0.72, 1, p), phase: B.phase, amp: 0.02 * (1 - ez), kind: B.kind)
                zoomLog = A.z0 + A.zs * ez * 0.55
                bgFrom = A.tint0; bgTo = A.tint1; bgT = ez
                if !A.ripDone, p > 0.5 { anim?.ripDone = true; rip = (Double(C.x), Double(C.y), t, 1) }
                if p >= 1 { finish(next: A.next, path: A.targetPath, tint: A.tint1, at: t) }
            case .zoomOut:
                let B = A.B!
                let ez = Self.easeIO(p)
                let s = pow(2, A.zs * (1 - ez))
                let sbx = Self.lerp(Double(C.x), B.x, ez), sby = Self.lerp(Double(C.y), B.y, ez)
                cam = (B.x - (sbx - Double(C.x)) / s, B.y - (sby - Double(C.y)) / s, s)
                for it in A.mapped { add(it, 1 - Self.sstep(0.5, 0.92, p), 0.5 * (1 - Self.sstep(0, 0.4, p))) }
                for it in A.sib { add(it, Self.sstep(0.3, 0.85, p), 0.5 * Self.sstep(0.5, 1, p), fly: (B.x, B.y, 0.9 * (1 - ez))) }
                add(B, Self.sstep(0.86, 1, p), 0.5 * Self.sstep(0.6, 1, p))
                let (bx, by) = S(B.x, B.y)
                let fadeEnd = 1 - Self.sstep(0.86, 1, p)
                membrane = Membrane(x: bx, y: by, r: B.r * s * (1 + 2.4 * pow(1 - Self.sstep(0, 0.72, p), 1.6)),
                                    body: Self.sstep(0.25, 0.8, p) * fadeEnd, rim: Self.sstep(0, 0.28, p) * fadeEnd, phase: B.phase, amp: 0.02 * ez, kind: B.kind)
                zoomLog = A.z0 - A.zs * ez * 0.55
                bgFrom = A.tint0; bgTo = A.tint1; bgT = ez
                if !A.ripDone, p > 0.12 { anim?.ripDone = true; rip = (Double(C.x), Double(C.y), t, 0.55) }
                if p >= 1 {
                    finish(next: A.next, path: A.targetPath, tint: A.tint1, at: t)
                    startZoomOut(at: t)
                }
            case .relayout:
                let ez = Self.easeIO(p)
                for (from, to) in A.pairs {
                    var it = to
                    it.x = Self.lerp(from.x, to.x, ez); it.y = Self.lerp(from.y, to.y, ez); it.r = Self.lerp(from.r, to.r, ez)
                    it.kids = p < 0.5 ? from.kids : to.kids
                    add(it, 1, 0.5 * abs(p - 0.5) * 2, ampMul: 1 + 1.4 * sin(.pi * p))
                }
                for g in A.gone {
                    var it = g
                    it.r = g.r * (1 + 0.25 * Self.sstep(0, 0.25, p) - 1.1 * Self.sstep(0.2, 0.7, p))
                    add(it, 1 - Self.sstep(0.25, 0.7, p), 0, ampMul: 3)
                }
                if p >= 1 { finish(next: A.next, path: path, tint: bg, at: t) }
            }
        } else {
            let h = hover.flatMap { n in items.first { $0.name == n } }
            for it in items {
                let hw = Self.lerp(hovW[it.id] ?? 0, h?.id == it.id ? 1 : 0, 0.14)
                hovW[it.id] = hw
                var target = CGPoint.zero
                if let h, h.id != it.id {
                    let dx = it.x - h.x, dy = it.y - h.y, dist = max(1, hypot(dx, dy))
                    let push = max(0, h.r * 1.04 + it.r + 24 - dist) * 0.55
                    target = CGPoint(x: dx / dist * push, y: dy / dist * push)
                }
                let o = off[it.id] ?? .zero
                off[it.id] = CGPoint(x: Self.lerp(o.x, target.x, 0.1), y: Self.lerp(o.y, target.y, 0.1))
                add(it, 1, 0.5, hov: hw)
            }
        }
        if anim == nil, pendingRelayout { pendingRelayout = false; relayout(at: t) }

        var ripple: Ripple?
        if let r = rip {
            let age = t - r.t0
            if age < 1.6, age >= 0 { ripple = Ripple(x: r.x, y: r.y, age: age, amp: r.amp * exp(-age * 2.2)) } else if age >= 1.6 { rip = nil }
        }
        if atRest { lastMains = mains }
        return BubbleFrame(mains: mains, droplets: drops, membrane: membrane, ripple: ripple, zoomLog: zoomLog,
                           bgFrom: bgFrom, bgTo: bgTo, bgT: bgT)
    }

    private func finish(next: [BubbleItem], path p: [String], tint: BgTint, at t: Double) {
        items = next
        path = p
        bg = tint
        anim = nil
        arrive = t
        off.removeAll(); hovW.removeAll()
    }

    // MARK: - Etkileşim

    /// Mevcut hover'ı 1,18r içinde korur (＋ düğmesine giderken titremesin).
    public func hitTest(_ p: CGPoint, current hover: String?) -> BubbleItem? {
        guard anim == nil else { return nil }
        if let h = hover, let m = lastMains.first(where: { $0.item.name == h }), hypot(p.x - m.x, p.y - m.y) < m.r * 1.18 { return m.item }
        return lastMains.first { $0.alpha > 0.6 && hypot(p.x - $0.x, p.y - $0.y) < $0.r }?.item
    }

    /// Etiket: r ≥ 30 ad + boyut, 17 ≤ r < 30 yalnızca boyut, daha küçükse yok.
    public func labelText(for item: BubbleItem, radius: Double) -> (name: String?, size: String)? {
        guard radius >= 17 else { return nil }
        let size = Fmt.size(item.size)
        guard radius >= 30 else { return (nil, size) }
        let maxc = max(4, Int(radius / 4.4))
        let name = item.name.count > maxc ? String(item.name.prefix(maxc - 1)) + "…" : item.name
        return (name, size)
    }
}
