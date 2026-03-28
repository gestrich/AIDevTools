import Foundation

public enum SkillSource: String, Codable, Sendable {
    case project
    case user
}

public struct SkillInfo: Codable, Identifiable, Sendable {
    public var id: String { path.absoluteString }
    public let name: String
    public let path: URL
    public let referenceFiles: [SkillReferenceFile]
    public let source: SkillSource

    public init(name: String, path: URL, referenceFiles: [SkillReferenceFile] = [], source: SkillSource = .project) {
        self.name = name
        self.path = path
        self.referenceFiles = referenceFiles
        self.source = source
    }

    public func relativePath(to repoRoot: URL) -> String {
        path.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
    }
}

public struct SkillReferenceFile: Codable, Hashable, Identifiable, Sendable {
    public var id: URL { url }
    public let name: String
    public let url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}
