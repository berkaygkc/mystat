import MystatCore
import SwiftUI

/// Bölüm başı: üst etiket, başlık, açıklama (mockup `headBlock`).
struct SectionHead: View {
    let kicker: String
    let title: AttributedString
    let soft: String?
    let lede: String?
    let level: Level
    let pulsing: Bool

    init(_ kicker: String, title: AttributedString, soft: String? = nil, lede: String? = nil, level: Level = .ok, pulsing: Bool = false) {
        self.kicker = kicker; self.title = title; self.soft = soft; self.lede = lede; self.level = level; self.pulsing = pulsing
    }
    init(_ kicker: String, title: String, soft: String? = nil, lede: String? = nil, level: Level = .ok, pulsing: Bool = false) {
        self.init(kicker, title: AttributedString(title), soft: soft, lede: lede, level: level, pulsing: pulsing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Kicker(kicker, level: level, pulsing: pulsing).padding(.bottom, 8)
            Headline(title, soft: soft?.trimmingCharacters(in: .whitespaces), size: 28, level: level == .ok ? .crit : level)
            if let lede {
                Text(lede).font(.system(size: 14)).lineSpacing(5).foregroundStyle(Theme.ink2)
                    .frame(maxWidth: 680, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
        }
    }
}

/// Kart başlığı satırı: solda kalın başlık, sağda soluk not ya da lejant.
struct SecH<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            Spacer()
            trailing()
        }
        .padding(.bottom, 10)
    }
}

extension SecH where Trailing == Text {
    init(_ title: String, note: String) {
        self.title = title
        self.trailing = { Text(note).font(.system(size: 12)).foregroundStyle(Theme.ink3) }
    }
}

struct Legend: View {
    let items: [(String, Color)]
    var body: some View {
        HStack(spacing: 14) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    Capsule().fill(items[i].1).frame(width: 10, height: 3)
                    Text(items[i].0)
                }
            }
        }
        .font(.system(size: 11.5)).foregroundStyle(Theme.ink2)
    }
}

/// Grafik kartının altındaki istatistik satırı (mockup `.stats`).
struct StatsRow: View {
    let items: [(String, String, String?)]
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(items[i].0).font(.system(size: 11)).foregroundStyle(Theme.ink3)
                    Text("\(Text(items[i].1).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundColor(Theme.ink))\(Text(items[i].2.map { " " + $0 } ?? "").font(.system(size: 11.5)).foregroundColor(Theme.ink3))")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 11).padding(.leading, i == 0 ? 0 : 14).padding(.trailing, 12)
                .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(Theme.line2).frame(width: 1) } }
            }
        }
        .padding(.top, 14)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line2).frame(height: 1).padding(.top, 14) }
    }
}

/// Mockup `.badge`: "sahipsiz".
struct OrphanBadge: View {
    var body: some View {
        Text("sahipsiz").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.orange)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .background(Theme.orangeSoft, in: Capsule())
    }
}

/// Yatay doluluk çubuğu.
struct Bar: View {
    let fraction: Double
    let color: Color
    let height: CGFloat
    var body: some View {
        GeometryReader { g in
            Capsule().fill(Theme.line2)
                .overlay(alignment: .leading) { Capsule().fill(color).frame(width: g.size.width * min(1, max(0, fraction))) }
        }
        .frame(height: height)
    }
}

extension View {
    func hairlineTop(_ color: Color = Theme.line) -> some View { overlay(alignment: .top) { Rectangle().fill(color).frame(height: 1) } }
    func hairlineBottom(_ color: Color = Theme.line) -> some View { overlay(alignment: .bottom) { Rectangle().fill(color).frame(height: 1) } }
}

/// Durum hapı (mockup `.pill`): "Normal", "Ilık", "Prizde", "Sakin".
struct Pill: View {
    let text: String
    let level: Level
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(level == .ok ? Theme.green : Theme.levelColor(level)).frame(width: 6, height: 6)
            Text(text)
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(level == .ok ? Theme.ink : Theme.levelColor(level))
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(level == .ok ? Theme.hover : Theme.orangeSoft, in: Capsule())
    }
}

/// Mockup `.hatch`: "kullanılmıyor" kısımlar için çapraz tarama.
struct Hatch: View {
    let base: Color
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            var p = Path()
            var x: CGFloat = -size.height
            while x < size.width { p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0)); x += 5 }
            ctx.stroke(p, with: .color(scheme == .dark ? .black.opacity(0.45) : .white.opacity(0.55)), lineWidth: 2)
        }
    }
}

/// Olgu satırı: solda etiket, sağda kalın değer.
struct FactRow: View {
    let k: String, v: String
    var body: some View {
        HStack(spacing: 12) {
            Text(k).foregroundStyle(Theme.ink2)
            Spacer(minLength: 8)
            Text(v).fontWeight(.semibold).monospacedDigit().foregroundStyle(Theme.ink).lineLimit(1)
        }
        .font(.system(size: 12.5)).padding(.vertical, 8).hairlineTop(Theme.line2)
    }
}
