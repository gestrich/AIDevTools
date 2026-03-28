import Foundation

public struct SkillContent: Sendable {
    public let frontMatter: [(key: String, value: String)]
    public let body: String

    public init(parsing raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else {
            self.frontMatter = []
            self.body = raw
            return
        }

        let afterOpening = trimmed.dropFirst(3)
        guard let closingRange = afterOpening.range(of: "\n---") else {
            self.frontMatter = []
            self.body = raw
            return
        }

        let yamlBlock = afterOpening[afterOpening.startIndex..<closingRange.lowerBound]
        let bodyStart = afterOpening[closingRange.upperBound...]
            .drop(while: { $0.isNewline })

        var pairs: [(key: String, value: String)] = []
        for line in yamlBlock.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            pairs.append((key: key, value: value))
        }

        self.frontMatter = pairs
        self.body = String(bodyStart)
    }
}
