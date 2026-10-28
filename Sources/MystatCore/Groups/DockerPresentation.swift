import Foundation

/// Docker bölümünün metinleri: eylem onayları ve bildirimleri.
public enum DockerPresentation {
    public static func confirm(_ a: DockerAction, disk d: DockerDisk) -> (title: String, message: String, confirm: String, destructive: Bool) {
        switch a {
        case .pruneAnonymousVolumes:
            return ("Kullanılmayan adsız volume'ler temizlensin mi?",
                    "Hiçbir container'a bağlı olmayan \(d.volumesAnonUnusedCount) adsız volume silinecek; \(Fmt.dec1(d.volumesAnonReclaimGB)) GB boşalacak. "
                        + "Adlı volume'lere ve çalışan container'lara dokunulmaz.", "Temizle", false)
        case .pruneAllVolumes:
            let n = max(0, d.volumesUnusedCount - d.volumesAnonUnusedCount), gb = max(0, d.volumesReclaimGB - d.volumesAnonReclaimGB)
            return ("Adlı volume'ler de silinsin mi?",
                    "Hiçbir container'a bağlı olmayan \(n) adlı volume silinecek; \(Fmt.dec1(gb)) GB boşalacak. "
                        + "Durdurulmuş compose projelerinin veritabanı verileri bunların içinde olabilir; geri alınamaz.", "Adlıları da sil", true)
        case .pruneImages:
            return ("Kullanılmayan image'lar temizlensin mi?",
                    "Hiçbir container'ın kullanmadığı \(d.imagesUnusedCount) image silinecek; \(Fmt.dec1(d.imagesReclaimGB)) GB boşalacak. "
                        + "Çalışan container'lar etkilenmez.", "Temizle", false)
        case .restart(_, let name):
            return ("\(name) yeniden başlatılsın mı?", "Container kısa bir süre kapanıp yeniden açılacak.", "Yeniden başlat", false)
        case .stop(_, let name):
            return ("\(name) durdurulsun mu?", "Container durdurulacak; Docker Desktop'tan ya da compose ile yeniden başlatılabilir.", "Durdur", true)
        }
    }

    /// Onaydan hemen sonra gösterilen ara bildirim.
    public static func progress(_ a: DockerAction) -> String {
        switch a { case .restart: "Yeniden başlatılıyor…"; case .stop: "Durduruluyor…"; default: "Temizleniyor…" }
    }

    public static func toast(_ a: DockerAction, _ o: DockerActionOutcome) -> String {
        switch (a, o) {
        case (_, .failed(let message)): message
        case (.restart(_, let name), .done): "\(name) yeniden başlatıldı"
        case (.stop(_, let name), .done): "\(name) durduruldu"
        case (_, .done(let gb)): (gb ?? 0) >= 0.05 ? "\(Fmt.dec1(gb ?? 0)) GB temizlendi" : "Temizlenecek bir şey kalmamış"
        }
    }
}

/// Container tablosunda bir compose projesi (projesizler "diğer container'lar").
public struct DockerProjectRow: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    /// CPU'ya göre azalan.
    public let containers: [Container]
    public let cpuPercent: Double, memoryGB: Double
    /// "15 container · hepsi çalışıyor" | "3 container · 1 sorunlu".
    public let summary: String
    /// Yeniden başlayan ya da sağlıksız container var.
    public let troubled: Bool
}

extension DockerPresentation {
    /// Sorunlu projeler önce, sonra CPU'ya göre.
    public static func projects(_ d: DockerState) -> [DockerProjectRow] {
        Dictionary(grouping: d.containers, by: \.project).map { project, cs in
            let bad = cs.filter { $0.restarting || !$0.healthy }.count
            return DockerProjectRow(name: project.isEmpty ? "diğer container'lar" : project,
                                    containers: cs.sorted { $0.cpuPercent > $1.cpuPercent },
                                    cpuPercent: cs.reduce(0) { $0 + $1.cpuPercent }, memoryGB: cs.reduce(0) { $0 + $1.memoryMB } / 1024,
                                    summary: "\(cs.count) container · " + (bad == 0 ? "hepsi çalışıyor" : "\(bad) sorunlu"), troubled: bad > 0)
        }
        .sorted { $0.troubled != $1.troubled ? $0.troubled : $0.cpuPercent != $1.cpuPercent ? $0.cpuPercent > $1.cpuPercent : $0.name < $1.name }
    }

    /// "27 GB · son 30 gün +9 GB": sanal disk dosyası (okunamazsa Docker'ın verisi) ve varsa gidişat.
    public static func diskNote(_ d: DockerState) -> String {
        let size = "\(Fmt.int(d.disk.rawGB ?? d.disk.dataGB)) GB"
        guard let t = d.trend30GB else { return size }
        return size + " · son 30 gün " + (t < 0 ? "−" : "+") + Fmt.int(abs(t)) + " GB"
    }
}
