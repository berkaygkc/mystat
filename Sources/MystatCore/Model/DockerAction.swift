import Foundation

/// Docker eylemleri (§7.4); hepsi onaylı. Volume temizliği kullanıcının kararıyla iki ayrı eylem: adsızlar (güvenli)
/// ve adlılar da (durmuş projelerin veri volume'leri; uyarılı).
public enum DockerAction: Sendable, Hashable {
    case restart(id: String, name: String)
    case stop(id: String, name: String)
    case pruneAnonymousVolumes, pruneAllVolumes, pruneImages

    public var isPrune: Bool {
        switch self { case .restart, .stop: false; case .pruneAnonymousVolumes, .pruneAllVolumes, .pruneImages: true }
    }
}

public enum DockerActionOutcome: Sendable, Equatable {
    /// Temizlikte API'nin bildirdiği gerçek boşalan alan.
    case done(reclaimedGB: Double?)
    case failed(String)
}
