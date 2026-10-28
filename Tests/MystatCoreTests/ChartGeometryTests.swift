import CoreGraphics
import Testing
@testable import MystatCore

@Suite struct ChartGeometryTests {
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
}
