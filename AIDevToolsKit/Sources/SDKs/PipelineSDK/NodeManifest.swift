public struct NodeManifest: Sendable {
    public let displayName: String
    public let id: String

    public init(id: String, displayName: String) {
        self.displayName = displayName
        self.id = id
    }
}
