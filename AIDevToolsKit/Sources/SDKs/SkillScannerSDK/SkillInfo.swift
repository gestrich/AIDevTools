import Foundation

public struct SkillInfo: Codable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let path: URL
    public let referenceFiles: [SkillReferenceFile]

    public init(name: String, path: URL, referenceFiles: [SkillReferenceFile] = []) {
        self.name = name
        self.path = path
        self.referenceFiles = referenceFiles
    }

    public func relativePath(to repoRoot: URL) -> String {
        path.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
    }
}

public struct SkillReferenceFile: Codable, Sendable {
    public let name: String
    public let url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}
