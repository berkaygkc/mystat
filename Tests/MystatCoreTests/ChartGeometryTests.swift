import CoreGraphics
import MystatTestSupport
import Testing
@testable import MystatCore

@Suite(.language("tr")) struct ChartGeometryTests {
    @Test func autoMaxAddsHeadroom() {
        #expect(ChartGeometry.autoMax([[2, 4], [10]]) == 11.5)
        #expect(ChartGeometry.autoMax([[0, 0]]) == 1)
    }
    @Test func mapping() {
        let g = ChartGeometry(count: 121, width: 600, plotHeight: 160, max: 100)
        #expect(g.x(0) == 0); #expect(g.x(120) == 600); #expect(g.x(60) == 300)
        #expect(g.y(100) == 4); #expect(g.y(0) == 160); #expect(g.y(150) == 4)   // tavanda kırpılır
    }
    @Test func hoverIndex() {
        let g = ChartGeometry(count: 121, width: 600, plotHeight: 160, max: 100)
        #expect(g.index(atX: 301) == 60); #expect(g.index(atX: -20) == 0); #expect(g.index(atX: 9999) == 120)
    }
    @Test func gridLabelY() {
        let g = ChartGeometry(count: 2, width: 100, plotHeight: 160, max: 100)
        #expect(g.labelY(fraction: 0.5) == 82); #expect(g.labelY(fraction: 1) == 10)
    }
    /// Canlı geçmiş başlangıçta kısadır: seri sağa yaslanır, "şimdi" hep sağ kenardadır.
    @Test func shortSeriesIsRightAligned() {
        let g = ChartGeometry(count: 30, capacity: 120, width: 1190, plotHeight: 100, max: 100)
        #expect(abs(g.x(29) - 1190) < 0.01)
        #expect(abs(g.x(0) - 1190 * 90.0 / 119.0) < 0.01)
        #expect(g.index(atX: 10) == 0)                 // verinin solunda: ilk nokta
        #expect(g.index(atX: 1190) == 29)
        #expect(ChartGeometry(count: 0, capacity: 120, width: 100, plotHeight: 10, max: 1).index(atX: 50) == nil)
    }

    /// Eksik noktalar (NaN) çizgiyi böler; ölçek onları yok sayar.
    @Test func missingPointsSplitTheLine() {
        let v = [1, .nan, .nan, 2, 3, .nan, 4]
        #expect(ChartGeometry.segments(v) == [0..<1, 3..<5, 6..<7])
        #expect(ChartGeometry.segments([.nan, .nan]).isEmpty)
        #expect(ChartGeometry.autoMax([v]) == 4 * 1.15)
    }
}
