import Foundation

public struct ReviewTemplateService: Sendable {
    public let reviewsDirectory: URL

    public init(reviewsDirectory: URL) {
        self.reviewsDirectory = reviewsDirectory
    }

    public func availableTemplates() throws -> [ReviewTemplate] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: reviewsDirectory,
            includingPropertiesForKeys: nil
        )
        return contents
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let id = url.deletingPathExtension().lastPathComponent
                let name = id.replacingOccurrences(of: "-", with: " ")
                return ReviewTemplate(id: id, name: name, url: url)
            }
    }

    public func loadSteps(from template: ReviewTemplate) throws -> [String] {
        let contents = try String(contentsOf: template.url, encoding: .utf8)
        return contents.components(separatedBy: .newlines).compactMap { line in
            if line.hasPrefix("## - [ ] ") {
                return String(line.dropFirst("## - [ ] ".count))
            } else if line.hasPrefix("## - [x] ") {
                return String(line.dropFirst("## - [x] ".count))
            }
            return nil
        }
    }
}

public struct ReviewTemplate: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let url: URL

    public init(id: String, name: String, url: URL) {
        self.id = id
        self.name = name
        self.url = url
    }
}
