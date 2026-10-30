import Foundation

/// Docker actions; all require confirmation. Volume cleanup is two separate actions: anonymous volumes (safe)
/// and named ones (data volumes of stopped projects; with a warning). Both are filtered by label and never touch each other's set.
public enum DockerAction: Sendable, Hashable {
    case restart(id: String, name: String)
    case stop(id: String, name: String)
    case pruneAnonymousVolumes, pruneNamedVolumes, pruneImages

    public var isPrune: Bool {
        switch self { case .restart, .stop: false; case .pruneAnonymousVolumes, .pruneNamedVolumes, .pruneImages: true }
    }
}

public enum DockerActionOutcome: Sendable, Equatable {
    /// Space actually freed, as reported by the API after cleanup.
    case done(reclaimedGB: Double?)
    case failed(String)
}
