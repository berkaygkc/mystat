import Foundation

/// Docker eylemleri (§7.4); hepsi onaylı. Volume temizliği kullanıcının kararıyla iki ayrı eylem: adsızlar (güvenli)
/// ve adlılar (durmuş projelerin veri volume'leri; uyarılı). İkisi de etiketle süzülür, birbirinin kümesine dokunmaz.
public enum DockerAction: Sendable, Hashable {
    case restart(id: String, name: String)
    case stop(id: String, name: String)
    case pruneAnonymousVolumes, pruneNamedVolumes, pruneImages

    public var isPrune: Bool {
        switch self { case .restart, .stop: false; case .pruneAnonymousVolumes, .pruneNamedVolumes, .pruneImages: true }
    }
}

public enum DockerActionOutcome: Sendable, Equatable {
    /// Temizlikte API'nin bildirdiği gerçek boşalan alan.
    case done(reclaimedGB: Double?)
    case failed(String)
}
