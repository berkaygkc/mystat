import Foundation

/// A mulberry32 generator with a fixed algorithm, so a given seed always produces the same series.
public struct Mulberry32: Sendable {
    private var state: UInt32
    public init(seed: UInt32) { state = seed }

    public mutating func next() -> Double {
        state = state &+ 0x6D2B_79F5
        var t = (state ^ (state >> 15)) &* (1 | state)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}

/// `walk`: a seeded, smoothed random walk.
func walk(_ seed: UInt32, _ n: Int, _ base: Double, _ amp: Double, smooth: Double = 0.72, lo: Double = 0, hi: Double = 100) -> [Double] {
    var r = Mulberry32(seed: seed); var v = base; var out: [Double] = []
    out.reserveCapacity(n)
    for _ in 0..<n {
        v = v * smooth + (base + (r.next() - 0.5) * amp * 2) * (1 - smooth)
        out.append(min(hi, max(lo, v)))
    }
    return out
}

/// `surge`: raises the last `k` points into the [lo, hi] band.
func surge(_ arr: [Double], _ k: Int, _ lo: Double, _ hi: Double, _ seed: UInt32) -> [Double] {
    var r = Mulberry32(seed: seed); let n = arr.count
    let ramp = max(1, min(8, Double(k) / 4))
    return arr.enumerated().map { i, v in
        if i < n - k { return v }
        let t = Double(i - (n - k)) / ramp
        let target = lo + r.next() * (hi - lo)
        return t < 1 ? v + (target - v) * t : target
    }
}
