import Foundation

/// Docker Engine API'den okunan ham değerler (probe ↔ core sözleşmesi). Anlam `DockerMeter`'da kurulur.

/// `/containers/json` satırı.
public struct DockerContainerRaw: Sendable, Equatable {
    /// `state`: "running", "restarting" …; `status`: "Up 2 days (healthy)".
    public let id, name, image, state, status: String
    /// `com.docker.compose.project` / `com.docker.compose.service` etiketleri.
    public let project: String?, service: String?

    public init(id: String, name: String, image: String, state: String, status: String, project: String?, service: String?) {
        self.id = id; self.name = name; self.image = image; self.state = state; self.status = status
        self.project = project; self.service = service
    }
}

/// `/containers/{id}/stats?stream=false&one-shot=true`: sayaçlar (fark bizde hesaplanır).
public struct DockerStatsRaw: Sendable, Equatable {
    public let id: String
    public let cpuTotal: UInt64, systemTotal: UInt64, onlineCPUs: Int
    public let memUsage: UInt64, memInactiveFile: UInt64

    public init(id: String, cpuTotal: UInt64, systemTotal: UInt64, onlineCPUs: Int, memUsage: UInt64, memInactiveFile: UInt64) {
        self.id = id; self.cpuTotal = cpuTotal; self.systemTotal = systemTotal; self.onlineCPUs = onlineCPUs
        self.memUsage = memUsage; self.memInactiveFile = memInactiveFile
    }
}

/// `/system/df`.
public struct DockerDFRaw: Sendable, Equatable {
    public struct Image: Sendable, Equatable {
        public let size: Int64, shared: Int64, containers: Int
        public init(size: Int64, shared: Int64, containers: Int) { self.size = size; self.shared = shared; self.containers = containers }
    }
    public struct Volume: Sendable, Equatable {
        /// `anonymous`: adı 64 onaltılık karakter (compose'un ve `-v /yol`'un adsız volume'leri).
        public let size: Int64, refCount: Int, anonymous: Bool
        public init(size: Int64, refCount: Int, anonymous: Bool) { self.size = size; self.refCount = refCount; self.anonymous = anonymous }
    }
    public struct Cache: Sendable, Equatable {
        public let size: Int64, inUse: Bool, shared: Bool
        public init(size: Int64, inUse: Bool, shared: Bool) { self.size = size; self.inUse = inUse; self.shared = shared }
    }
    public let layersSize: Int64
    public let images: [Image], volumes: [Volume], buildCache: [Cache]
    public let containersRw: Int64

    public init(layersSize: Int64, images: [Image], volumes: [Volume], buildCache: [Cache], containersRw: Int64) {
        self.layersSize = layersSize; self.images = images; self.volumes = volumes; self.buildCache = buildCache; self.containersRw = containersRw
    }
}

/// `/info`: sanal makinenin tahsisi.
public struct DockerInfoRaw: Sendable, Equatable {
    public let ncpu: Int, memTotal: Int64
    public init(ncpu: Int, memTotal: Int64) { self.ncpu = ncpu; self.memTotal = memTotal }
}
