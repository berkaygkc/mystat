import AppKit
import MystatCore
import SwiftUI

/// Renk ve tipografi tokenları. Değerler mockup'taki `:root` (açık) ve `body.dark` (koyu) CSS değişkenleri.
public enum Theme {
    public static func dyn(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    static func rgba(_ r: Int, _ g: Int, _ b: Int, _ a: Double = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
    }

    public static let ink = dyn(rgba(29, 29, 31), rgba(245, 245, 247))
    public static let ink2 = dyn(rgba(60, 60, 67, 0.76), rgba(235, 235, 245, 0.70))
    public static let ink3 = dyn(rgba(60, 60, 67, 0.46), rgba(235, 235, 245, 0.40))
    public static let line = dyn(rgba(60, 60, 67, 0.13), rgba(255, 255, 255, 0.10))
    public static let line2 = dyn(rgba(60, 60, 67, 0.08), rgba(255, 255, 255, 0.06))
    public static let red = dyn(rgba(215, 0, 21), rgba(255, 69, 58))
    public static let redSoft = dyn(rgba(255, 59, 48, 0.09), rgba(255, 69, 58, 0.13))
    public static let redEdge = dyn(rgba(255, 59, 48, 0.22), rgba(255, 69, 58, 0.26))
    public static let orange = dyn(rgba(201, 52, 0), rgba(255, 159, 10))
    public static let orangeSoft = dyn(rgba(255, 149, 0, 0.14), rgba(255, 159, 10, 0.15))
    public static let green = dyn(rgba(36, 138, 61), rgba(48, 209, 88))
    public static let sel = dyn(rgba(120, 120, 128, 0.15), rgba(255, 255, 255, 0.11))
    public static let hover = dyn(rgba(120, 120, 128, 0.08), rgba(255, 255, 255, 0.055))
    public static let card = dyn(rgba(255, 255, 255, 0.55), rgba(255, 255, 255, 0.045))
    public static let cardEdge = dyn(rgba(0, 0, 0, 0.055), rgba(255, 255, 255, 0.07))
    public static let chart = dyn(rgba(58, 58, 60), rgba(229, 229, 234))
    public static let chart2 = dyn(rgba(60, 60, 67, 0.38), rgba(235, 235, 245, 0.36))
    public static let c1 = dyn(rgba(88, 86, 214), rgba(125, 122, 255))
    public static let c2 = dyn(rgba(88, 86, 214, 0.60), rgba(125, 122, 255, 0.62))
    public static let c3 = dyn(rgba(88, 86, 214, 0.32), rgba(125, 122, 255, 0.34))
    public static let c4 = dyn(rgba(60, 60, 67, 0.09), rgba(255, 255, 255, 0.07))
    public static let seg = dyn(rgba(120, 120, 128, 0.13), rgba(255, 255, 255, 0.08))
    public static let segOn = dyn(rgba(255, 255, 255), rgba(255, 255, 255, 0.18))
    public static let btn = dyn(rgba(255, 255, 255, 0.8), rgba(255, 255, 255, 0.08))
    public static let btnEdge = dyn(rgba(0, 0, 0, 0.09), rgba(255, 255, 255, 0.10))
    public static let tip = dyn(rgba(255, 255, 255, 0.86), rgba(44, 44, 48, 0.9))
    public static let acc = dyn(rgba(0, 113, 227), rgba(10, 132, 255))
    public static let accSoft = dyn(rgba(0, 113, 227, 0.12), rgba(10, 132, 255, 0.18))
    public static let inv = dyn(rgba(255, 255, 255), rgba(28, 28, 30))

    /// Seviyeye göre vurgu rengi; `.ok` için birincil metin.
    public static func levelColor(_ l: Level) -> Color { l == .crit ? red : l == .warn ? orange : ink }

    public enum Fonts {
        public static func kicker() -> Font { .system(size: 10.5, weight: .semibold) }
        /// Mockup'taki 650 ağırlığı (semibold 0,3 ile bold 0,4 arası).
        public static func headline(_ size: CGFloat = 28) -> Font { Font(NSFont.systemFont(ofSize: size, weight: NSFont.Weight(0.35))) }
        public static func big(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .light).monospacedDigit() }
        public static func body(_ size: CGFloat = 13.5, _ w: Font.Weight = .regular) -> Font { .system(size: size, weight: w) }
    }
}
