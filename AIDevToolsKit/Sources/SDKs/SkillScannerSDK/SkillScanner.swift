import Foundation

public struct SkillScanner: Sendable {

    public init() {}

    static let skillsDirectories = [".agents/skills", ".claude/skills"]

    public func scanSkills(at repositoryPath: URL) throws -> [SkillInfo] {
        var skillsByName: [String: SkillInfo] = [:]

        var visited: Set<String> = []

        for relative in Self.skillsDirectories {
            let skillsDirectory = repositoryPath.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: skillsDirectory.path) else { continue }

            let resolved = skillsDirectory.resolvingSymlinksInPath()
            guard visited.insert(resolved.path).inserted else { continue }

            let contents = try FileManager.default.contentsOfDirectory(
                at: resolved,
                includingPropertiesForKeys: [.isDirectoryKey]
            )

            for item in contents {
                let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory {
                    let skillFile = item.appendingPathComponent("SKILL.md")
                    if FileManager.default.fileExists(atPath: skillFile.path) {
                        let name = item.lastPathComponent
                        if skillsByName[name] == nil {
                            let refs = findReferenceFiles(in: item)
                            skillsByName[name] = SkillInfo(name: name, path: item, referenceFiles: refs)
                        }
                    }
                } else if item.pathExtension == "md" {
                    let name = item.deletingPathExtension().lastPathComponent
                    if skillsByName[name] == nil {
                        skillsByName[name] = SkillInfo(name: name, path: item)
                    }
                }
            }
        }

        return skillsByName.values.sorted { $0.name < $1.name }
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
