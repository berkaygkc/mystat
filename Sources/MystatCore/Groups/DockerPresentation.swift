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
