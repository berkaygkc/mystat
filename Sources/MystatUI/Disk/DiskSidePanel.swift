import MystatCore
import SwiftUI

/// The list to the right of the disk map and the "Selected" basket.
struct DiskSidePanel<Source: MetricsSource>: View {
    let source: Source
    @Bindable var disk: DiskUIState
    @Bindable var state: MonitorState
    @State private var hovered: String?

    var body: some View {
        let tree = source.diskTree
        let node = tree.node(at: disk.path) ?? tree.root
        let here = disk.basket.state(of: disk.path)
        // While scanning, the same accumulated sizes as the map's bubbles; the header is the sum of the rows.
        let kids = node.children ?? []
        let total = scanProgress == nil ? node.size : kids.reduce(0) { $0 + scanned($1) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(node.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                if source.snapshot.capabilities.diskScan {
                    Text(Fmt.size(total)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.ink3)
                }
            }
            .padding(.top, 4).padding(.bottom, 10)
            if here != .none {
                Text(L10n.t(here == .selected ? "disk.side.allSelected" : "disk.side.implied"))
                    .font(.system(size: 12)).lineSpacing(2).foregroundStyle(Theme.acc)
                    .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous)).padding(.bottom, 8)
            }
            if !source.snapshot.capabilities.diskScan {
                Text(L10n.t("disk.side.unavailable")).font(.system(size: 12)).foregroundStyle(Theme.ink3)
            } else if case .none = source.diskScan.effective(now: Date()) {
                Text(L10n.t("disk.side.startScan")).font(.system(size: 12)).foregroundStyle(Theme.ink3)
            } else {
                let sorted = kids.sorted { $0.size > $1.size }
                if sorted.count > Self.plainRows {   // a real scan can have thousands of rows (node_modules)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(sorted.indices, id: \.self) { i in row(sorted[i], tree: tree) }
                        }
                    }
                    .frame(height: CGFloat(Self.plainRows) * Self.rowHeight)
                } else {
                    ForEach(sorted, id: \.name) { c in row(c, tree: tree) }
                }
                basket(tree).padding(.top, 14)
            }
        }
        .frame(width: 300, alignment: .leading)
    }

    static var plainRows: Int { 12 }
    static var rowHeight: CGFloat { 33 }

    private var scanProgress: Double? {
        if source.diskScanSimulated, case .scanning(let p, _, _) = source.diskScan { return p }
        return nil
    }

    private func scanned(_ c: DiskNode) -> Double {
        BubbleEngine.scannedSize(c.size, path: disk.path + [c.name], progress: scanProgress)
    }

    private func row(_ c: DiskNode, tree: DiskTree) -> some View {
        let p = disk.path + [c.name]
        let st = disk.basket.state(of: p)
        let other = c.kind == .other
        let folder = c.canHaveChildren
        let locked = DeletionGuard.reason(path: p)
        var name = c.displayName
        if case .other(let n)? = c.ref { name += L10n.plural("disk.smallFiles", n, ["n": Fmt.int(Double(n))]) }
        return HStack(spacing: 8) {
            Group {
                if other { Color.clear }
                else if let locked {   // protected: cannot be selected, but its contents can
                    Image(systemName: "lock.fill").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.ink3).help(locked)
                } else { CheckCircle(state: st) { disk.toggle(p, tree: tree) } }
            }
            .frame(width: 18, height: 18)
            Circle().fill(Theme.kindColor(c.kind)).frame(width: 8, height: 8)
            Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(other ? Theme.ink2 : Theme.ink).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            Text(Fmt.size(scanned(c))).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ink2)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.ink3).opacity(folder ? 1 : 0).frame(width: 16)
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(hovered == c.name && !other ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .onHover { h in hovered = h ? c.name : nil; disk.hoverName = h ? c.name : nil }
        .onTapGesture {
            guard !other else { return }
            if folder { disk.open(p) } else { disk.toggle(p, tree: tree) }
        }
    }

    @ViewBuilder
    private func basket(_ tree: DiskTree) -> some View {
        let items = disk.basket.items
        if items.isEmpty {
            Text(L10n.t("disk.side.hint"))
                .font(.system(size: 12)).lineSpacing(3).foregroundStyle(Theme.ink3).fixedSize(horizontal: false, vertical: true)
        } else {
            let hasDocker = items.contains { $0.kind == .docker || $0.path.contains("Docker") }
            Card(radius: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(L10n.t("disk.basket.title")).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.ink)
                        Text(L10n.plural("disk.items", items.count) + " · " + Fmt.size(disk.basket.totalGB)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.ink2)
                        Spacer()
                        Text(L10n.t("disk.basket.clear")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink2)
                            .onTapGesture { disk.basket.clear() }
                    }
                    .padding(.bottom, 8)
                    let list = VStack(spacing: 0) {
                            ForEach(items, id: \.path) { it in
                                HStack(spacing: 9) {
                                    Circle().fill(Theme.kindColor(it.kind)).frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(it.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                                        Text("~/" + it.path.dropLast().joined(separator: "/")).font(.system(size: 11)).foregroundStyle(Theme.ink3).lineLimit(1).truncationMode(.head)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture { disk.open(Array(it.path.dropLast())) }
                                    Spacer(minLength: 6)
                                    Text(Fmt.size(it.size)).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ink)
                                    Image(systemName: "xmark").font(.system(size: 9.5, weight: .bold)).foregroundStyle(Theme.ink3)
                                        .frame(width: 18, height: 18).contentShape(Rectangle())
                                        .onTapGesture { disk.basket.remove(it.path) }
                                }
                                .padding(.vertical, 7).hairlineTop(Theme.line2)
                            }
                        }
                    if items.count > 5 { ScrollView { list }.frame(height: 200) } else { list }
                    if hasDocker {
                        Text(L10n.t("disk.basket.dockerWarning"))
                            .font(.system(size: 12)).lineSpacing(3).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 11).padding(.vertical, 9)
                            .background(Theme.orangeSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .padding(.top, 10).fixedSize(horizontal: false, vertical: true)
                    }
                    if disk.basket.cloudItems > 0 {   // items that live in the cloud: warn before deleting
                        Text(L10n.plural("disk.basket.cloud", disk.basket.cloudItems, ["n": Fmt.int(Double(disk.basket.cloudItems))]))
                            .font(.system(size: 12)).lineSpacing(3).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 11).padding(.vertical, 9)
                            .background(Theme.orangeSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .padding(.top, 10).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 7) {
                        Seg([(DeleteMode.permanent, L10n.t("disk.mode.permanent")), (DeleteMode.trash, L10n.t("disk.mode.trash"))], selection: $disk.mode).fixedSize()
                        Btn(disk.basket.buttonTitle(mode: disk.mode), style: disk.mode == .permanent ? .dangerFill : .primary) {
                            state.confirm = disk.confirmDelete(tree: tree, source: source)
                        }
                    }
                    .padding(.top, 12)
                }
            }
        }
    }
}

/// Selection circle: empty, selected (blue ✓), or selected via its parent folder (faded blue ✓).
struct CheckCircle: View {
    let state: SelState
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        ZStack {
            switch state {
            case .selected: Circle().fill(Theme.acc)
            case .implied: Circle().fill(Theme.accSoft)
            case .none: Circle().strokeBorder(hover ? Theme.acc : Theme.ink3, lineWidth: 1.5)
            }
            if state != .none {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(state == .selected ? Color.white : Theme.acc)
            }
        }
        .frame(width: 18, height: 18)
        .contentShape(Circle())
        .onHover { hover = $0 }
        .onTapGesture { if state != .implied { action() } }
    }
}
