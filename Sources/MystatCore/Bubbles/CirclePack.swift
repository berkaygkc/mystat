import Foundation

public struct PackCircle: Sendable, Equatable {
    public var x: Double, y: Double, r: Double
    public init(x: Double, y: Double, r: Double) { self.x = x; self.y = y; self.r = r }
}

/// A child and the values of its grandchildren (if any). A child without grandchildren is a leaf.
public struct PackInput: Sendable {
    public let value: Double
    public let grandchildren: [Double]
    public init(value: Double, grandchildren: [Double] = []) { self.value = value; self.grandchildren = grandchildren }
}

/// Port of d3-hierarchy 3.1.2 `pack` (src/pack/siblings.js, enclose.js, index.js; src/lcg.js, array.js).
/// d3-hierarchy is ISC-licensed, Copyright 2010-2021 Mike Bostock; see THIRD_PARTY_NOTICES.md.
/// Layouts match d3's output exactly.
public enum CirclePack {
    // MARK: - Randomness (d3 lcg)

    struct LCG {
        var s: UInt64 = 1
        mutating func next() -> Double {
            s = (1_664_525 &* s &+ 1_013_904_223) % 4_294_967_296
            return Double(s) / 4_294_967_296
        }
    }

    final class Circ {
        var x = 0.0, y = 0.0, r: Double
        init(r: Double) { self.r = r }
    }

    final class FNode {
        let c: Circ
        var next: FNode!
        var previous: FNode!
        init(_ c: Circ) { self.c = c }
    }

    // MARK: - siblings.js

    static func place(_ b: Circ, _ a: Circ, _ c: Circ) {
        let dx = b.x - a.x, dy = b.y - a.y, d2 = dx * dx + dy * dy
        if d2 != 0 {
            var a2 = a.r + c.r; a2 *= a2
            var b2 = b.r + c.r; b2 *= b2
            if a2 > b2 {
                let x = (d2 + b2 - a2) / (2 * d2), y = (max(0, b2 / d2 - x * x)).squareRoot()
                c.x = b.x - x * dx - y * dy
                c.y = b.y - x * dy + y * dx
            } else {
                let x = (d2 + a2 - b2) / (2 * d2), y = (max(0, a2 / d2 - x * x)).squareRoot()
                c.x = a.x + x * dx - y * dy
                c.y = a.y + x * dy + y * dx
            }
        } else {
            c.x = a.x + c.r
            c.y = a.y
        }
    }

    static func intersects(_ a: Circ, _ b: Circ) -> Bool {
        let dr = a.r + b.r - 1e-6, dx = b.x - a.x, dy = b.y - a.y
        return dr > 0 && dr * dr > dx * dx + dy * dy
    }

    static func score(_ node: FNode) -> Double {
        let a = node.c, b = node.next.c, ab = a.r + b.r
        let dx = (a.x * b.r + b.x * a.r) / ab, dy = (a.y * b.r + b.y * a.r) / ab
        return dx * dx + dy * dy
    }

    static func packSiblingsRandom(_ circles: [Circ], _ random: inout LCG) -> Double {
        let n = circles.count
        guard n > 0 else { return 0 }
        let first = circles[0]
        first.x = 0; first.y = 0
        guard n > 1 else { return first.r }
        let second = circles[1]
        first.x = -second.r; second.x = first.r; second.y = 0
        guard n > 2 else { return first.r + second.r }
        place(second, first, circles[2])

        var a = FNode(first), b = FNode(second)
        let c0 = FNode(circles[2])
        // The front chain is circular (next/previous); if it is not broken on return, nodes and circles leak.
        var nodes = [a, b, c0]
        defer { for nd in nodes { nd.next = nil; nd.previous = nil } }
        a.next = b; c0.previous = b
        b.next = c0; a.previous = c0
        c0.next = a; b.previous = a

        var i = 3
        pack: while i < n {
            place(a.c, b.c, circles[i])
            let c = FNode(circles[i])
            nodes.append(c)
            var j: FNode = b.next, k: FNode = a.previous
            var sj = b.c.r, sk = a.c.r
            repeat {
                if sj <= sk {
                    if intersects(j.c, c.c) { b = j; a.next = b; b.previous = a; continue pack }
                    sj += j.c.r; j = j.next
                } else {
                    if intersects(k.c, c.c) { a = k; a.next = b; b.previous = a; continue pack }
                    sk += k.c.r; k = k.previous
                }
            } while j !== k.next

            c.previous = a; c.next = b
            a.next = c; b.previous = c; b = c

            var aa = score(a)
            var cur: FNode = c.next
            while cur !== b {
                let ca = score(cur)
                if ca < aa { a = cur; aa = ca }
                cur = cur.next
            }
            b = a.next
            i += 1
        }

        var chain = [PackCircle(x: b.c.x, y: b.c.y, r: b.c.r)]
        var cur: FNode = b.next
        while cur !== b { chain.append(PackCircle(x: cur.c.x, y: cur.c.y, r: cur.c.r)); cur = cur.next }
        let e = packEncloseRandom(chain, &random)
        for ci in circles { ci.x -= e.x; ci.y -= e.y }
        return e.r
    }

    /// Places sibling circles (d3 `packSiblings`).
    public static func packSiblings(_ radii: [Double]) -> [PackCircle] {
        let circles = radii.map { Circ(r: $0) }
        var random = LCG()
        _ = packSiblingsRandom(circles, &random)
        return circles.map { PackCircle(x: $0.x, y: $0.y, r: $0.r) }
    }

    // MARK: - enclose.js

    public static func enclose(_ circles: [PackCircle]) -> PackCircle {
        var random = LCG()
        return packEncloseRandom(circles, &random)
    }

    static func packEncloseRandom(_ input: [PackCircle], _ random: inout LCG) -> PackCircle {
        var circles = input
        var m = circles.count
        while m > 0 {   // d3 array.js shuffle
            let i = Int(random.next() * Double(m))
            m -= 1
            circles.swapAt(m, i)
        }
        var i = 0, basis: [PackCircle] = [], e: PackCircle?
        while i < circles.count {
            let p = circles[i]
            if let ee = e, enclosesWeak(ee, p) { i += 1 } else {
                basis = extendBasis(basis, p)
                e = encloseBasis(basis)
                i = 0
            }
        }
        return e ?? PackCircle(x: 0, y: 0, r: 0)
    }

    static func extendBasis(_ B: [PackCircle], _ p: PackCircle) -> [PackCircle] {
        if enclosesWeakAll(p, B) { return [p] }
        for i in B.indices where enclosesNot(p, B[i]) && enclosesWeakAll(encloseBasis2(B[i], p), B) { return [B[i], p] }
        for i in 0..<max(0, B.count - 1) {
            for j in (i + 1)..<B.count
            where enclosesNot(encloseBasis2(B[i], B[j]), p) && enclosesNot(encloseBasis2(B[i], p), B[j])
                && enclosesNot(encloseBasis2(B[j], p), B[i]) && enclosesWeakAll(encloseBasis3(B[i], B[j], p), B) {
                return [B[i], B[j], p]
            }
        }
        return [p]   // d3 throws an error here; the safest choice for a numerical edge case
    }

    static func enclosesNot(_ a: PackCircle, _ b: PackCircle) -> Bool {
        let dr = a.r - b.r, dx = b.x - a.x, dy = b.y - a.y
        return dr < 0 || dr * dr < dx * dx + dy * dy
    }

    static func enclosesWeak(_ a: PackCircle, _ b: PackCircle) -> Bool {
        let dr = a.r - b.r + max(a.r, b.r, 1) * 1e-9, dx = b.x - a.x, dy = b.y - a.y
        return dr > 0 && dr * dr > dx * dx + dy * dy
    }

    static func enclosesWeakAll(_ a: PackCircle, _ B: [PackCircle]) -> Bool { B.allSatisfy { enclosesWeak(a, $0) } }

    static func encloseBasis(_ B: [PackCircle]) -> PackCircle {
        switch B.count {
        case 1: B[0]
        case 2: encloseBasis2(B[0], B[1])
        default: encloseBasis3(B[0], B[1], B[2])
        }
    }

    static func encloseBasis2(_ a: PackCircle, _ b: PackCircle) -> PackCircle {
        let x21 = b.x - a.x, y21 = b.y - a.y, r21 = b.r - a.r
        let l = (x21 * x21 + y21 * y21).squareRoot()
        return PackCircle(x: (a.x + b.x + x21 / l * r21) / 2, y: (a.y + b.y + y21 / l * r21) / 2, r: (l + a.r + b.r) / 2)
    }

    static func encloseBasis3(_ a: PackCircle, _ b: PackCircle, _ c: PackCircle) -> PackCircle {
        let x1 = a.x, y1 = a.y, r1 = a.r, x2 = b.x, y2 = b.y, r2 = b.r, x3 = c.x, y3 = c.y, r3 = c.r
        let a2 = x1 - x2, a3 = x1 - x3, b2 = y1 - y2, b3 = y1 - y3, c2 = r2 - r1, c3 = r3 - r1
        let d1 = x1 * x1 + y1 * y1 - r1 * r1
        let d2 = d1 - x2 * x2 - y2 * y2 + r2 * r2
        let d3 = d1 - x3 * x3 - y3 * y3 + r3 * r3
        let ab = a3 * b2 - a2 * b3
        let xa = (b2 * d3 - b3 * d2) / (ab * 2) - x1, xb = (b3 * c2 - b2 * c3) / ab
        let ya = (a3 * d2 - a2 * d3) / (ab * 2) - y1, yb = (a2 * c3 - a3 * c2) / ab
        let A = xb * xb + yb * yb - 1, Bq = 2 * (r1 + xa * xb + ya * yb), C = xa * xa + ya * ya - r1 * r1
        let r = -(abs(A) > 1e-6 ? (Bq + (Bq * Bq - 4 * A * C).squareRoot()) / (2 * A) : C / Bq)
        return PackCircle(x: x1 + xa + xb * r, y: y1 + ya + yb * r, r: r)
    }

    // MARK: - index.js (two levels: `pack().size([s, s]).padding(d => d.depth === 0 ? root : child)`)

    /// Children and grandchildren must be given in descending order of value (like `.sort` in d3).
    /// Returns the child circles within the `[0, size]` square, each with its grandchildren.
    public static func layout(children: [PackInput], size: Double, rootPadding: Double, childPadding: Double) -> [(PackCircle, [PackCircle])] {
        let kids = children.map { Circ(r: $0.grandchildren.isEmpty ? $0.value.squareRoot() : 0) }
        let grands = children.map { $0.grandchildren.map { Circ(r: $0.squareRoot()) } }
        var random = LCG()

        // pass 1: no padding (k = 1)
        for (i, g) in grands.enumerated() where !g.isEmpty { kids[i].r = packSiblingsRandom(g, &random) }
        var rootR = packSiblingsRandom(kids, &random)

        // pass 2: padding, scale k = root radius / size
        let k = rootR / size
        for (i, g) in grands.enumerated() where !g.isEmpty {
            let pad = childPadding * k
            g.forEach { $0.r += pad }
            let e = packSiblingsRandom(g, &random)
            g.forEach { $0.r -= pad }
            kids[i].r = e + pad
        }
        let pad = rootPadding * k
        kids.forEach { $0.r += pad }
        let e = packSiblingsRandom(kids, &random)
        kids.forEach { $0.r -= pad }
        rootR = e + pad

        // Translate and scale (root center at size/2)
        let t = size / (2 * rootR), cx = size / 2, cy = size / 2
        return kids.indices.map { i in
            let kc = PackCircle(x: cx + t * kids[i].x, y: cy + t * kids[i].y, r: kids[i].r * t)
            let gc = grands[i].map { PackCircle(x: kc.x + t * $0.x, y: kc.y + t * $0.y, r: $0.r * t) }
            return (kc, gc)
        }
    }
}
