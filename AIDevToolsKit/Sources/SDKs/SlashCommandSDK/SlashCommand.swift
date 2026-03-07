import Foundation

public struct SlashCommand: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
        self.id = name
    }
}
