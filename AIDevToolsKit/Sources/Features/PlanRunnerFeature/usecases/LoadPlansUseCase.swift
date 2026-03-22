import Foundation
import PlanRunnerService

public struct LoadPlansUseCase: Sendable {

    public init() {}

    public func run(proposedDirectory: URL) async -> [PlanEntry] {
        await Task.detached {
            self.loadFromDisk(proposedDirectory: proposedDirectory)
        }.value
    }

    private func loadFromDisk(proposedDirectory: URL) -> [PlanEntry] {
        let fm = FileManager.default

        guard fm.fileExists(atPath: proposedDirectory.path),
              let files = try? fm.contentsOfDirectory(
                  at: proposedDirectory,
                  includingPropertiesForKeys: [.creationDateKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "md" }
            .compactMap { url -> PlanEntry? in
                let (completed, total) = parsePhaseCount(from: url)
                guard total > 0 else { return nil }
                let date = fileCreationDate(url)
                return PlanEntry(
                    planURL: url,
                    completedPhases: completed,
                    totalPhases: total,
                    creationDate: date
                )
            }
            .sorted { $0.name < $1.name }
    }

    private func parsePhaseCount(from url: URL) -> (completed: Int, total: Int) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return (0, 0) }
        var completed = 0
        var total = 0
        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("## - [x] ") {
                completed += 1
                total += 1
            } else if line.hasPrefix("## - [ ] ") {
                total += 1
            }
        }
        return (completed, total)
    }

    private func fileCreationDate(_ url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.creationDate] as? Date
    }
}
