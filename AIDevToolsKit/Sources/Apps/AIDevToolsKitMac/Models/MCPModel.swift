import DataPathsService
import Foundation

enum MCPStatus {
    case binaryMissing
    case notConfigured
    case ready(binaryURL: URL, builtAt: Date)

    var daysStale: Int? {
        guard case .ready(_, let builtAt) = self else { return nil }
        return Calendar.current.dateComponents([.day], from: builtAt, to: .now).day
    }
}

@MainActor @Observable
final class MCPModel {

    private let settingsModel: SettingsModel

    init(settingsModel: SettingsModel) {
        self.settingsModel = settingsModel
    }

    var status: MCPStatus {
        let fm = FileManager.default

        let siblingURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("ai-dev-tools-kit")

        var candidates: [URL] = []
        if fm.fileExists(atPath: siblingURL.path) {
            candidates.append(siblingURL)
        }

        if let repoPath = settingsModel.aiDevToolsRepoPath {
            let swiftBuildURL = repoPath
                .appendingPathComponent("AIDevToolsKit")
                .appendingPathComponent(".build")
                .appendingPathComponent("debug")
                .appendingPathComponent("ai-dev-tools-kit")
            if fm.fileExists(atPath: swiftBuildURL.path) {
                candidates.append(swiftBuildURL)
            }
        }

        if candidates.isEmpty {
            if settingsModel.aiDevToolsRepoPath == nil {
                return .notConfigured
            }
            return .binaryMissing
        }

        let mostRecent = candidates.max(by: { a, b in
            let aDate = (try? fm.attributesOfItem(atPath: a.path)[.modificationDate] as? Date) ?? .distantPast
            let bDate = (try? fm.attributesOfItem(atPath: b.path)[.modificationDate] as? Date) ?? .distantPast
            return aDate < bDate
        })!

        let builtAt = (try? fm.attributesOfItem(atPath: mostRecent.path)[.modificationDate] as? Date) ?? .distantPast
        return .ready(binaryURL: mostRecent, builtAt: builtAt)
    }

    func writeMCPConfigIfNeeded() {
        guard case .ready(let binaryURL, _) = status else { return }
        let config = """
        {
          "mcpServers": {
            "ai-dev-tools-kit": {
              "command": "\(binaryURL.path)",
              "args": ["mcp"]
            }
          }
        }
        """
        let fileURL = DataPathsService.mcpConfigFileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? config.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
