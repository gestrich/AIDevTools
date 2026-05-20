import Foundation

public struct SkillScanner: Sendable {

    public init() {}

    static let commandsDirectories = [".agents/commands", ".claude/commands"]
    static let skillsDirectories = [".agents/skills", ".claude/skills"]

    public static let defaultGlobalCommandsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/commands")

    public static let defaultGlobalSkillsDirectories: [URL] = [
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agents/skills"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills")
    ]

    public func scanSkills(
        at repositoryPath: URL,
        globalCommandsDirectory: URL? = defaultGlobalCommandsDirectory,
        globalSkillsDirectories: [URL] = defaultGlobalSkillsDirectories
    ) throws -> [SkillInfo] {
        var skills: [SkillInfo] = []
        var visited: Set<String> = []

        // Skills directories (project)
        for relative in Self.skillsDirectories {
            let skillsDirectory = repositoryPath.appendingPathComponent(relative)
            skills.append(contentsOf: try scanSkillsDirectory(skillsDirectory, source: .project, visited: &visited))
        }

        // Local commands directories (project)
        for relative in Self.commandsDirectories {
            let commandsDirectory = repositoryPath.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: commandsDirectory.path) else { continue }

            let resolved = commandsDirectory.resolvingSymlinksInPath()
            guard visited.insert(resolved.path).inserted else { continue }

            skills.append(contentsOf: scanCommandsDirectory(resolved, source: .project))
        }

        // Global commands directory (user)
        if let globalDir = globalCommandsDirectory,
           FileManager.default.fileExists(atPath: globalDir.path) {
            let resolved = globalDir.resolvingSymlinksInPath()
            if visited.insert(resolved.path).inserted {
                skills.append(contentsOf: scanCommandsDirectory(resolved, source: .user))
            }
        }

        // Global skills directories (user)
        for globalSkillsDir in globalSkillsDirectories {
            skills.append(contentsOf: try scanSkillsDirectory(globalSkillsDir, source: .user, visited: &visited))
        }

        // Precedence: project skills win over user skills when names collide.
        let projectFirst = skills.filter { $0.source == .project } + skills.filter { $0.source == .user }
        var seen: Set<String> = []
        let deduplicated = projectFirst.filter { seen.insert($0.name).inserted }
        return deduplicated.sorted { $0.name < $1.name }
    }

    private func scanSkillsDirectory(
        _ directory: URL,
        source: SkillSource,
        visited: inout Set<String>
    ) throws -> [SkillInfo] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }

        let resolved = directory.resolvingSymlinksInPath()
        guard visited.insert(resolved.path).inserted else { return [] }

        let contents = try FileManager.default.contentsOfDirectory(
            at: resolved,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        var results: [SkillInfo] = []
        for item in contents {
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                // Normalize: Linux adds trailing slash to directory URLs from contentsOfDirectory
                let itemPath = item.path
                let normalized = URL(fileURLWithPath: itemPath.hasSuffix("/") ? String(itemPath.dropLast()) : itemPath)
                let skillFile = normalized.appendingPathComponent("SKILL.md")
                if FileManager.default.fileExists(atPath: skillFile.path) {
                    let name = normalized.lastPathComponent
                    let refs = findReferenceFiles(in: normalized)
                    results.append(SkillInfo(name: name, path: normalized, referenceFiles: refs, source: source))
                }
            } else if item.pathExtension == "md" {
                let name = item.deletingPathExtension().lastPathComponent
                results.append(SkillInfo(name: name, path: item, source: source))
            }
        }
        return results
    }

    public func filterSkills(_ skills: [SkillInfo], query: String) -> [SkillInfo] {
        guard !query.isEmpty else { return skills }

        let searchQuery = query.hasPrefix("/") ? String(query.dropFirst()) : query
        let lowercaseQuery = searchQuery.lowercased()

        let scored: [(skill: SkillInfo, score: Int)] = skills.compactMap { skill in
            let score = scoreSkill(skill.name, query: lowercaseQuery)
            return score > 0 ? (skill, score) : nil
        }

        return scored
            .sorted { $0.score > $1.score }
            .map(\.skill)
    }

    private func scoreSkill(_ skillName: String, query: String) -> Int {
        let lowercaseName = skillName.lowercased()
        let segments = skillName.split(separator: "/").map { String($0) }
        let lowercaseSegments = segments.map { $0.lowercased() }

        var bestScore = 0

        for (index, segment) in lowercaseSegments.enumerated() {
            if segment == query {
                return 1000 - (index * 10)
            } else if segment.hasPrefix(query) {
                let score = 500 - (index * 10) - (segment.count - query.count)
                bestScore = max(bestScore, score)
            } else if segment.contains(query) {
                if let range = segment.range(of: query) {
                    let distanceFromStart = segment.distance(from: segment.startIndex, to: range.lowerBound)
                    let score = 250 - (index * 10) - distanceFromStart
                    bestScore = max(bestScore, score)
                }
            }
        }

        if bestScore == 0 && lowercaseName.contains(query) {
            if let range = lowercaseName.range(of: query) {
                let distanceFromStart = lowercaseName.distance(from: lowercaseName.startIndex, to: range.lowerBound)
                bestScore = 100 - distanceFromStart
            }
        }

        return bestScore
    }

    private func scanCommandsDirectory(_ directory: URL, source: SkillSource) -> [SkillInfo] {
        let resolved = directory.resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(
            at: resolved,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        var results: [SkillInfo] = []
        let basePath = resolved.path + "/"

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "md" else { continue }
            let resolvedFile = fileURL.resolvingSymlinksInPath()
            let relativePath = resolvedFile.path.replacingOccurrences(of: basePath, with: "")
            let name = (relativePath as NSString).deletingPathExtension
            results.append(SkillInfo(name: name, path: resolvedFile, source: source))
        }

        return results
    }

    private func findReferenceFiles(in directory: URL) -> [SkillReferenceFile] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return items
            .filter { $0.pathExtension == "md" && $0.lastPathComponent != "SKILL.md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { SkillReferenceFile(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
    }
}
