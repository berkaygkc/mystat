import AppKit
import CoreText
import MystatTestSupport
import Testing
@testable import MystatUI

/// Intermediate weights such as 650/550 must not be rounded to a named weight
/// (`NSFont.systemFont(weight: 0.35)` silently yields Bold 700).
@Suite(.language("tr")) struct FontWeightTests {
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
