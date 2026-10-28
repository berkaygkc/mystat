import MystatCore
import SwiftUI

/// Docker (mockup `secDocker`).
struct DockerSection<Source: MetricsSource>: View {
    let source: Source
    @Bindable var state: MonitorState
    /// Kullanıcı bir projeyi açıp kapatana kadar varsayılan: ilk satır ve sorunlu olanlar açık.
    @State private var openProjects: Set<String>?
    @State private var hovered: String?

    var body: some View {
        let s = source.snapshot, d = s.docker
        let h = SectionText.docker(s)
        let cpu = d.containers.reduce(0) { $0 + $1.cpuPercent }
        let mem = d.containers.reduce(0) { $0 + $1.memoryMB } / 1024
        let busy = d.containers.contains { $0.cpuPercent >= 30 }
        VStack(alignment: .leading, spacing: 0) {
            SectionHead("DOCKER", title: h.title, soft: h.soft, lede: h.lede, level: h.level, pulsing: h.level != .ok)
            if s.capabilities.docker && d.running { content(s, d, cpu: cpu, mem: mem, busy: busy) }
        }
    }

    @ViewBuilder
    private func content(_ s: Snapshot, _ d: DockerState, cpu: Double, mem: Double, busy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if s.incident?.kind == .docker { IncidentBlock(source: source, state: state, inOverview: false).padding(.top, 20) }
            HStack(alignment: .top, spacing: 18) {
                Card {
                    VStack(alignment: .leading, spacing: 0) {
                        SecH(title: "Container'ların toplam kullanımı") { Legend(items: [("CPU", Theme.chart)]) }
                        AreaChart(series: [ChartSeries(source.series(.dockerCPU, range: state.range), color: busy ? Theme.red : Theme.chart, fill: true, name: "CPU")],
                                  max: 100, height: 160, range: state.range, format: Fmt.pct, formatY: Fmt.pct)
                        StatsRow(items: [("CPU", Fmt.pct(cpu), Fmt.dec1(cpu / 100) + " çekirdek"), ("Bellek", Fmt.dec1(mem) + " GB", nil),
                                         ("Sanal makine", Fmt.dec1(d.vmMemoryGB) + " GB", "\(d.vmCores) çekirdek")])
                    }
                }
                .frame(maxWidth: .infinity)
                diskCard(d).frame(minWidth: 360, idealWidth: 420, maxWidth: 440)
            }
            .padding(.top, 22)
            containers(d, cpu: cpu, mem: mem).padding(.top, 26)
        }
    }

    private func diskCard(_ d: DockerState) -> some View {
        let k = d.disk
        let segs: [(Double, Color, Bool)] = [(k.imagesGB - k.imagesReclaimGB, Theme.c1, false), (k.imagesReclaimGB, Theme.c1, true),
                                            (k.volumesGB - k.volumesReclaimGB, Theme.c2, false), (k.volumesReclaimGB, Theme.c2, true),
                                            (k.buildCacheGB + k.containersGB, Theme.c4, false)].map { (max(0, $0.0), $0.1, $0.2) }
        let named = max(0, k.volumesReclaimGB - k.volumesAnonReclaimGB)
        let trend = source.series(.dockerTrend30, range: .m10)
        let top = trend.filter(\.isFinite).max() ?? 0
        return Card {
            VStack(alignment: .leading, spacing: 0) {
                SecH("Docker'ın diski", note: DockerPresentation.diskNote(d))
                GeometryReader { g in
                    let total = max(0.001, segs.reduce(0) { $0 + $1.0 }), gaps = CGFloat(segs.count - 1) * 2
                    HStack(spacing: 2) {
                        ForEach(segs.indices, id: \.self) { i in
                            Group { if segs[i].2 { Hatch(base: segs[i].1) } else { Rectangle().fill(segs[i].1) } }
                                .frame(width: (g.size.width - gaps) * segs[i].0 / total)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .frame(height: 12).padding(.vertical, 10)
                diskRow(Theme.c1, "Image'lar · \(k.imagesCount)", Fmt.dec1(k.imagesReclaimGB) + " GB kullanılmıyor", Fmt.dec1(k.imagesGB) + " GB")
                diskRow(Theme.c2, "Volume'ler · \(k.volumesCount)", Fmt.dec1(k.volumesReclaimGB) + " GB kullanılmıyor", Fmt.dec1(k.volumesGB) + " GB")
                diskRow(Theme.c4, "Build cache", k.buildCacheReclaimGB >= 0.05 ? Fmt.dec1(k.buildCacheReclaimGB) + " GB kullanılmıyor" : nil,
                        Fmt.int(k.buildCacheGB) + " GB")
                diskRow(Theme.c4, "Sanal disk dosyası", nil, k.rawGB.map { Fmt.int($0) + " GB" } ?? "—")
                Sparkline(trend, color: Theme.c1, height: 34, max: top <= 30 ? 30 : top * 1.15, fillOpacity: 0.2).padding(.top, 10)
                VStack(spacing: 7) {
                    cleanButton("Adsız volume'leri temizle", k.volumesAnonReclaimGB) { state.confirm = DockerActions.request(.pruneAnonymousVolumes, disk: k, source: source) }
                    // Kullanıcının kararı: durmuş projelerin adlı veri volume'leri ayrı ve uyarılı düğmede.
                    cleanButton("Adlı volume'leri de temizle", named, danger: true) { state.confirm = DockerActions.request(.pruneAllVolumes, disk: k, source: source) }
                    cleanButton("Kullanılmayan image'ları temizle", k.imagesReclaimGB) { state.confirm = DockerActions.request(.pruneImages, disk: k, source: source) }
                }
                .padding(.top, 12)
            }
        }
    }

    private func diskRow(_ c: Color, _ label: String, _ reclaim: String?, _ size: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 8, height: 8).frame(width: 12, alignment: .leading)
            Text(label).foregroundStyle(Theme.ink)
            Spacer()
            if let reclaim { Text(reclaim).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.orange) }
            Text(size).monospacedDigit().foregroundStyle(Theme.ink2).frame(minWidth: 64, alignment: .trailing)
        }
        .font(.system(size: 12.5)).padding(.vertical, 6).hairlineTop(Theme.line2)
    }

    private func cleanButton(_ title: String, _ gb: Double, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(danger ? Theme.red : Theme.ink)
                Spacer()
                Text(Fmt.dec1(gb) + " GB").font(.system(size: 12.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, 13).frame(height: 30)
            .background(Theme.btn, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.btnEdge, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(gb < 0.05)
        .opacity(gb < 0.05 ? 0.45 : 1)
    }

    private func containers(_ d: DockerState, cpu: Double, mem: Double) -> some View {
        let rows = DockerPresentation.projects(d)
        let open = openProjects ?? Set(rows.enumerated().filter { $0.offset == 0 || $0.element.troubled }.map(\.element.name))
        return VStack(alignment: .leading, spacing: 0) {
            SecH("Container'lar", note: "compose projesine göre")
            ForEach(rows) { r in
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.ink3)
                        .rotationEffect(.degrees(open.contains(r.name) ? 90 : 0)).frame(width: 18)
                    Text("\(Text(r.name).fontWeight(.semibold).foregroundColor(Theme.ink))  \(Text(r.summary).font(.system(size: 12.5)).foregroundColor(r.troubled ? Theme.red : Theme.ink2))")
                        .font(.system(size: 13.5))
                    Spacer()
                    Text("\(Fmt.pct(r.cpuPercent)) CPU · \(Fmt.dec1(r.memoryGB)) GB").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ink2)
                }
                .padding(.horizontal, 10).frame(minHeight: 42)
                .contentShape(Rectangle())
                .onTapGesture {
                    var next = open
                    if next.contains(r.name) { next.remove(r.name) } else { next.insert(r.name) }
                    withAnimation(.easeOut(duration: 0.2)) { openProjects = next }
                }
                if open.contains(r.name) {
                    row(cells: ["", "Servis", "Image", "CPU · %100 = 1 çek.", "Bellek", "Süre"], header: true)
                    ForEach(r.containers) { c in containerRow(c) }
                }
            }
        }
    }

    private func row(cells: [String], header: Bool) -> some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 18)
            Text(cells[1]).frame(maxWidth: .infinity, alignment: .leading)
            Text(cells[2]).frame(maxWidth: .infinity, alignment: .leading)
            Text(cells[3]).frame(width: 110, alignment: .trailing)
            Text(cells[4]).frame(width: 76, alignment: .trailing)
            Text(cells[5]).frame(width: 64, alignment: .trailing)
            Color.clear.frame(width: 72)
        }
        .font(.system(size: 11)).foregroundStyle(Theme.ink3).padding(.horizontal, 10).padding(.bottom, 6)
    }

    private func containerRow(_ c: Container) -> some View {
        let hot = c.cpuPercent > 30
        return HStack(spacing: 10) {
            Circle().fill(c.restarting || !c.healthy ? Theme.red : Theme.green).frame(width: 7, height: 7).frame(width: 18)
            Text(c.name).fontWeight(.semibold).foregroundStyle(Theme.ink).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(c.image).foregroundStyle(Theme.ink2).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(Fmt.pct(c.cpuPercent)).fontWeight(hot ? .semibold : .regular).foregroundStyle(hot ? Theme.red : Theme.ink).frame(width: 110, alignment: .trailing)
            Text(Fmt.int(c.memoryMB) + " MB").foregroundStyle(Theme.ink).frame(width: 76, alignment: .trailing)
            Text(c.uptime).foregroundStyle(Theme.ink).frame(width: 64, alignment: .trailing)
            HStack(spacing: 4) {
                smallButton("arrow.clockwise", danger: false) { state.confirm = DockerActions.request(.restart(id: c.id, name: c.name), disk: source.snapshot.docker.disk, source: source) }
                smallButton("stop.fill", danger: true) { state.confirm = DockerActions.request(.stop(id: c.id, name: c.name), disk: source.snapshot.docker.disk, source: source) }
            }
            .frame(width: 72, alignment: .trailing).opacity(hovered == c.id ? 1 : 0)
        }
        .font(.system(size: 12.5).monospacedDigit())
        .padding(.horizontal, 10).frame(minHeight: 38)
        .background(hovered == c.id ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovered = $0 ? c.id : (hovered == c.id ? nil : hovered) }
    }

    private func smallButton(_ icon: String, danger: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(danger ? Theme.red : Theme.ink)
                .frame(width: 28, height: 24)
                .background(Theme.btn, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.btnEdge, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

/// Docker eylemlerinin onay penceresi: onaylanınca ara bildirim, sonuç gelince gerçek sonucun bildirimi.
@MainActor
public enum DockerActions {
    public static func request(_ action: DockerAction, disk: DockerDisk, source: any MetricsSource) -> ConfirmRequest {
        let c = DockerPresentation.confirm(action, disk: disk)
        return ConfirmRequest(title: c.title, message: c.message, confirm: c.confirm, destructive: c.destructive, onConfirm: {
            ToastCenter.shared.show(DockerPresentation.progress(action))
            Task { @MainActor in ToastCenter.shared.show(DockerPresentation.toast(action, await source.perform(action))) }
        })
    }
}
