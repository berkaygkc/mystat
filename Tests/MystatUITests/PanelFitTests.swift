import AppKit
import MystatCore
import MystatTestSupport
import Testing
@testable import MystatUI

/// The second line of the English panel cells must fit on one line (the Turkish measurements came from the design; some of those are already truncated there).
@MainActor @Suite(.language("en")) struct PanelFitTests {
    /// Panel is 352 pt, horizontal padding 2 × 22; cells split the width in half, with 14 pt padding right of the left cell and 16 pt left of the right cell.
    static let widths: [CGFloat] = [154 - 14, 154 - 16]

    static func width(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11.5)]).width }

    @Test func memorySubFitsAtEveryPressure() {
        for level in [Level.ok, .warn, .crit] {
            var snap = SampleSource(seed: 1).snapshot
            snap.memory.pressureLevel = level; snap.memory.usedGB = 47.9
            let s = PanelPresentation.cells(snap)[1].sub
            #expect(Self.width(s) <= Self.widths[1], "\(s): \(Self.width(s))")
        }
    }

    /// During a long-running incident the CPU cell (left column) must fit too.
    @Test func longIncidentCPUSubFits() {
        for m in [1, 35, 120] {
            let dur = L10n.plural("dur.forShort", m)
            for s in [L10n.t("panel.cpu.above", ["for": dur, "pct": Fmt.pct(100)]), L10n.t("panel.cpu.busy", ["for": dur])] {
                #expect(Self.width(s) <= Self.widths[0], "\(s): \(Self.width(s))")
            }
        }
    }

    @Test func sampleCellSubsFit() {
        var snaps = [SampleSource(seed: 1).snapshot]
        for k in IncidentKind.allCases { snaps.append(SampleSource(seed: 1, incident: true, kind: k).snapshot) }
        for s in snaps {
            for (i, c) in PanelPresentation.cells(s).enumerated() {
                #expect(Self.width(c.sub) <= Self.widths[i % 2], "\(c.section): \(c.sub) \(Self.width(c.sub))")
            }
        }
    }
}
