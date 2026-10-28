import AppKit
import Testing
@testable import MystatUI

/// Etiket görüntüsü mockup `.bm-l` kutusunu izler: ad satırı 1,15·fs, 2 pt boşluk, boyut satırı doğal yükseklikte;
/// hale gölgesi için her yanda pay; merkez kutunun merkezidir.
@MainActor @Suite struct BubbleLabelImageTests {
    @Test func boxMatchesCssLayout() {
        let fs = 19.0
        let img = BubbleLabelImage.make(name: "Library", size: "96 GB", fontSize: fs, dark: false, scale: 2)
        let sizeFont = Theme.Fonts.sf(fs * 0.78, wght: 550, tabular: true)
        let sizeLine = Double(sizeFont.ascender - sizeFont.descender + sizeFont.leading)
        let boxH = 1.15 * fs + 2 + sizeLine
        #expect(abs(Double(img.size.height) - (boxH + 2 * BubbleLabelImage.pad)) < 1)
        #expect(img.image.width == Int((img.size.width * 2).rounded()))
        #expect(img.size.width > 60 && img.size.width < 120 + 2 * BubbleLabelImage.pad)
    }

    @Test func sizeOnlyLabelIsSingleLine() {
        let img = BubbleLabelImage.make(name: nil, size: "3,1 GB", fontSize: 11, dark: true, scale: 1)
        let f = Theme.Fonts.sf(11 * 0.78, wght: 550, tabular: true)
        #expect(abs(Double(img.size.height) - (Double(f.ascender - f.descender + f.leading) + 2 * BubbleLabelImage.pad)) < 1)
    }

    @Test func textIsDrawnInTheMiddle() {
        let img = BubbleLabelImage.make(name: "Documents", size: "52 GB", fontSize: 19, dark: false, scale: 1)
        let rep = NSBitmapImageRep(cgImage: img.image)
        // Merkez satırında koyu (metin) piksel olmalı; köşe yalnızca hale (açık) ya da boş.
        var dark = 0
        for x in 0..<rep.pixelsWide { if let c = rep.colorAt(x: x, y: rep.pixelsHigh / 2 - 6), c.alphaComponent > 0.5, c.brightnessComponent < 0.4 { dark += 1 } }
        #expect(dark > 10)
        #expect((rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 0) < 0.05)
    }
}
