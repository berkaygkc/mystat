import AppKit
import SwiftUI
import MystatTestSupport
import Testing
@testable import MystatUI

/// Üzerine gelince yalnızca dikey çizgi, noktalar ve ipucu eklenir; grafiğin kendisi yerinden oynamamalı.
@MainActor @Suite(.language("tr")) struct AreaChartHoverTests {
    func render(_ hover: CGFloat?) -> NSBitmapImageRep {
        let values = (0..<60).map { 30 + 20 * sin(Double($0) / 5) }
        let chart = AreaChart(series: [ChartSeries(values, color: .black, fill: true, name: "toplam")], max: 100, height: 180,
                              range: .m10, format: { "\(Int($0))" }, formatY: { "%\(Int($0))" }, hoverAt: hover)
            .frame(width: 600, height: 180).background(Color.white)
        let r = ImageRenderer(content: chart)
        r.scale = 1
        return NSBitmapImageRep(cgImage: r.cgImage!)
    }

    @Test func hoverDoesNotMoveThePlot() {
        let calm = render(nil), hovered = render(480)
        var differing = 0
        for x in 0..<300 {
            for y in 20..<150 {
                let a = calm.colorAt(x: x, y: y)!, b = hovered.colorAt(x: x, y: y)!
                if abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent) > 0.02 { differing += 1 }
            }
        }
        #expect(differing == 0)
    }
}
