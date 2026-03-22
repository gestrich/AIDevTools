import Foundation
import SkillScannerSDK

public struct Skill: Codable, Sendable {
    public let name: String
    public let path: URL
    public let referenceFiles: [ReferenceFile]
    public let source: SkillSource

    public init(name: String, path: URL, referenceFiles: [ReferenceFile] = [], source: SkillSource = .project) {
        self.name = name
        self.path = path
        self.referenceFiles = referenceFiles
        self.source = source
    }
}

public struct ReferenceFile: Codable, Sendable, Identifiable, Hashable {
    public var id: URL { url }
    public let name: String
    public let url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}
