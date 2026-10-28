import CoreGraphics

/// Alan grafiğinin ölçek ve konum hesabı (mockup'taki `drawChart`).
public struct ChartGeometry: Sendable {
    public let count: Int
    public let width: CGFloat
    public let plotHeight: CGFloat
    public let max: Double

    public init(count: Int, width: CGFloat, plotHeight: CGFloat, max: Double) {
        self.count = count; self.width = width; self.plotHeight = plotHeight; self.max = max
    }

    /// Verilmezse en büyük değer × 1,15; hepsi sıfırsa 1.
    public static func autoMax(_ series: [[Double]]) -> Double {
        let m = series.flatMap { $0 }.max() ?? 0
        return m > 0 ? m * 1.15 : 1
    }

    public func x(_ i: Int) -> CGFloat { count > 1 ? CGFloat(i) / CGFloat(count - 1) * width : 0 }

    /// Üstte 4 pt pay bırakır; tavanı aşan değer kırpılır.
    public func y(_ v: Double) -> CGFloat { plotHeight - CGFloat(Swift.min(v, max) / max) * (plotHeight - 4) }

    public func index(atX px: CGFloat) -> Int {
        guard count > 1, width > 0 else { return 0 }
        let clamped = Swift.max(0, Swift.min(width, px))
        return Int((clamped / width * CGFloat(count - 1)).rounded())
    }

    /// Sağdaki ızgara etiketinin dikey merkezi.
    public func labelY(fraction f: Double) -> CGFloat {
        plotHeight - CGFloat(f) * (plotHeight - 4) + (f == 1 ? 6 : 0)
    }
}
