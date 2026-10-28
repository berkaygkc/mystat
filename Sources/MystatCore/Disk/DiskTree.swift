import Foundation

/// Disk ağacının bir düğümü. Boyut GB cinsinden.
public final class DiskNode {
    public let name: String
    public var size: Double
    public let isFile: Bool
    public let isDocker: Bool
    public var children: [DiskNode]?

    public init(_ name: String, _ size: Double, file: Bool = false, docker: Bool = false, _ children: [DiskNode]? = nil) {
        self.name = name; self.size = size; self.isFile = file; self.isDocker = docker; self.children = children
    }
}

public final class DiskTree {
    public let root: DiskNode
    public init(root: DiskNode) { self.root = root }
}
