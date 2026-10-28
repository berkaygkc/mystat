import MystatCore
import SwiftUI

/// Docker (mockup `secDocker`).
struct DockerSection<Source: MetricsSource>: View {
    let source: Source
    @Bindable var state: MonitorState
    @State private var projectOpen = true
    @State private var hovered: String?

    var body: some View {
        let s = source.snapshot, d = s.docker
        let h = SectionText.docker(s)
        let cpu = d.containers.reduce(0) { $0 + $1.cpuPercent }
        let mem = d.containers.reduce(0) { $0 + $1.memoryMB } / 1024
        let busy = d.containers.contains { $0.cpuPercent >= 30 }
        VStack(alignment: .leading, spacing: 0) {
            SectionHead("DOCKER", title: h.title, soft: h.soft, lede: h.lede, level: h.level, pulsing: h.level != .ok)
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
                                            (k.volumesGB - k.volumesReclaimGB, Theme.c2, false), (k.volumesReclaimGB, Theme.c2, true), (1.3, Theme.c4, false)]
        return Card {
            VStack(alignment: .leading, spacing: 0) {
                SecH("Docker'ın diski", note: "\(Fmt.int(k.rawGB)) GB · son 30 gün +9 GB")
                GeometryReader { g in
                    let total = segs.reduce(0) { $0 + $1.0 }, gaps = CGFloat(segs.count - 1) * 2
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
                diskRow(Theme.c4, "Build cache", nil, Fmt.int(k.buildCacheGB) + " GB")
                diskRow(Theme.c4, "Sanal disk dosyası", nil, Fmt.int(k.rawGB) + " GB")
                Sparkline(source.series(.dockerTrend30, range: .m10), color: Theme.c1, height: 34, max: 30, fillOpacity: 0.2).padding(.top, 10)
                VStack(spacing: 7) {
                    cleanButton("Kullanılmayan volume'leri temizle", k.volumesReclaimGB) { state.confirm = DockerActions.prune(volumes: true, gb: k.volumesReclaimGB) }
                    cleanButton("Kullanılmayan image'ları temizle", k.imagesReclaimGB) { state.confirm = DockerActions.prune(volumes: false, gb: k.imagesReclaimGB) }
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

    private func cleanButton(_ title: String, _ gb: Double, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text(Fmt.dec1(gb) + " GB").font(.system(size: 12.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, 13).frame(height: 30)
            .background(Theme.btn, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.btnEdge, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func containers(_ d: DockerState, cpu: Double, mem: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SecH("Container'lar", note: "compose projesine göre")
            HStack(spacing: 10) {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.ink3)
                    .rotationEffect(.degrees(projectOpen ? 90 : 0)).frame(width: 18)
                Text("\(Text(d.project).fontWeight(.semibold).foregroundColor(Theme.ink))  \(Text("\(d.containers.count) container · hepsi çalışıyor").font(.system(size: 12.5)).foregroundColor(Theme.ink2))")
                    .font(.system(size: 13.5))
                Spacer()
                Text("\(Fmt.pct(cpu)) CPU · \(Fmt.dec1(mem)) GB").font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Theme.ink2)
            }
            .padding(.horizontal, 10).frame(minHeight: 42)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { projectOpen.toggle() } }
            if projectOpen {
                row(cells: ["", "Servis", "Image", "CPU · %100 = 1 çek.", "Bellek", "Süre"], header: true)
                ForEach(d.containers.sorted { $0.cpuPercent > $1.cpuPercent }) { c in containerRow(c) }
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
            Circle().fill(Theme.green).frame(width: 7, height: 7).frame(width: 18)
            Text(c.name).fontWeight(.semibold).foregroundStyle(Theme.ink).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(c.image).foregroundStyle(Theme.ink2).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(Fmt.pct(c.cpuPercent)).fontWeight(hot ? .semibold : .regular).foregroundStyle(hot ? Theme.red : Theme.ink).frame(width: 110, alignment: .trailing)
            Text(Fmt.int(c.memoryMB) + " MB").foregroundStyle(Theme.ink).frame(width: 76, alignment: .trailing)
            Text(c.uptime).foregroundStyle(Theme.ink).frame(width: 64, alignment: .trailing)
            HStack(spacing: 4) {
                smallButton("arrow.clockwise", danger: false) { ToastCenter.shared.show("\(c.name) yeniden başlatılıyor… (örnek)") }
                smallButton("stop.fill", danger: true) { ToastCenter.shared.show("\(c.name) durduruluyor… (örnek)") }
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

@MainActor
public enum DockerActions {
    public static func prune(volumes: Bool, gb: Double) -> ConfirmRequest {
        ConfirmRequest(
            title: "Kullanılmayan " + (volumes ? "volume'ler" : "image'lar") + " temizlensin mi?",
            message: (volumes ? "Hiçbir container'a bağlı olmayan 177 volume silinecek" : "Hiçbir container'ın kullanmadığı 4 image silinecek")
                + "; \(Fmt.dec1(gb)) GB boşalacak. Çalışan container'lar etkilenmez.",
            confirm: "Temizle", destructive: true,
            onConfirm: { ToastCenter.shared.show("\(Fmt.dec1(gb)) GB temizlendi (örnek)") })
    }
}
