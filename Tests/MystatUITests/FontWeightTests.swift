import AppKit
import CoreText
import Testing
@testable import MystatUI

/// Mockup'taki 650/550 gibi ara ağırlıklar adlandırılmış ağırlığa yuvarlanmamalı
/// (`NSFont.systemFont(weight: 0.35)` sessizce Bold 700 veriyor).
@Suite struct FontWeightTests {
    func wght(_ f: NSFont) -> Double? {
        let v = CTFontCopyVariation(f as CTFont) as? [NSNumber: NSNumber]
        return v?[NSNumber(value: 0x7767_6874)]?.doubleValue
    }
    @Test func cssWeightIsExact() {
        #expect(wght(Theme.Fonts.sf(28, wght: 650)) == 650)
        #expect(wght(Theme.Fonts.sf(11, wght: 550, tabular: true)) == 550)
    }
    @Test func headlineIs650() {
        #expect(wght(Theme.Fonts.headlineNSFont(28)) == 650)
    }
}
