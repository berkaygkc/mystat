import CoreGraphics

/// Alan grafiğinin ölçek ve konum hesabı (mockup'taki `drawChart`).
/// Seri `capacity`'den kısaysa (canlı geçmiş yeni başladıysa) sağa yaslanır: son nokta hep sağ kenarda.
public struct ChartGeometry: Sendable {
    public let count: Int
    public let capacity: Int
    public let width: CGFloat
    public let plotHeight: CGFloat
    public let max: Double

    public init(count: Int, capacity: Int? = nil, width: CGFloat, plotHeight: CGFloat, max: Double) {
        self.count = count; self.capacity = Swift.max(count, capacity ?? count)
        self.width = width; self.plotHeight = plotHeight; self.max = max
    }

    private var offset: Int { capacity - count }

    /// Verilmezse en büyük değer × 1,15; hepsi sıfırsa 1.
    public static func autoMax(_ series: [[Double]]) -> Double {
        let m = series.flatMap { $0 }.filter(\.isFinite).max() ?? 0
        return m > 0 ? m * 1.15 : 1
    }

    /// Kesintisiz parçalar: eksik nokta (NaN; uyku, kapalı kalma) çizgiyi böler, boşluk düz çizgiyle köprülenmez.
    public static func segments(_ v: [Double]) -> [Range<Int>] {
        var out: [Range<Int>] = [], start: Int?
        for (i, x) in v.enumerated() {
            if x.isFinite { if start == nil { start = i } } else if let s = start { out.append(s..<i); start = nil }
        }
        if let s = start { out.append(s..<v.count) }
        return out
    }

    public func x(_ i: Int) -> CGFloat { capacity > 1 ? CGFloat(i + offset) / CGFloat(capacity - 1) * width : 0 }

    /// Üstte 4 pt pay bırakır; tavanı aşan değer kırpılır.
    public func y(_ v: Double) -> CGFloat { plotHeight - CGFloat(Swift.min(v, max) / max) * (plotHeight - 4) }

    /// Boş seride `nil`; verinin solunda kalan noktalar ilk değere düşer.
    public func index(atX px: CGFloat) -> Int? {
        guard count > 0 else { return nil }
        guard capacity > 1, width > 0 else { return 0 }
        let clamped = Swift.max(0, Swift.min(width, px))
        let slot = Int((clamped / width * CGFloat(capacity - 1)).rounded())
        return Swift.min(count - 1, Swift.max(0, slot - offset))
    }

    /// Sağdaki ızgara etiketinin dikey merkezi.
    public func labelY(fraction f: Double) -> CGFloat {
        plotHeight - CGFloat(f) * (plotHeight - 4) + (f == 1 ? 6 : 0)
    }
}
