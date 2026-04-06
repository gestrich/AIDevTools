import ArgumentParser
import ClaudeChainFeature
import ClaudeChainService
import ClaudeCLISDK
import Foundation

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List local chain projects without requiring GitHub access"
    )

    @Option(name: .long, help: "Path to the repository containing claude-chain/")
    var repoPath: String?

    @Option(name: .long, help: "Filter by kind: spec, sweep, or all (default: all)")
    var kind: String?

    public init() {}

    public func run() async throws {
        let path: String
        if let repoPath {
            path = (repoPath as NSString).standardizingPath
        } else if let envPath = ProcessInfo.processInfo.environment["CLAUDECHAIN_REPO_PATH"] {
            path = envPath
        } else {
            path = FileManager.default.currentDirectoryPath
        }

        let repoURL = URL(fileURLWithPath: path)
        let chainKind = try resolveKind(kind)
        let chainService = ClaudeChainService(client: ClaudeProvider(), repoPath: repoURL)
        let result = try await chainService.listChains(source: .local, kind: chainKind)

        for failure in result.failures {
            fputs("Warning: \(failure.localizedDescription)\n", stderr)
        }

        if result.projects.isEmpty {
            print("No chain projects found in \(repoURL.lastPathComponent)")
            return
        }

        let sorted = result.projects.sorted { $0.name < $1.name }
        let maxNameLen = sorted.map(\.name.count).max() ?? 0

        for project in sorted {
            let padded = project.name.padding(toLength: maxNameLen, withPad: " ", startingAt: 0)
            let badge = project.kind == .sweep ? "sweep" : "spec"
            print("  \(padded)  [\(badge)]")
        }

        print("\n\(result.projects.count) project(s)")
    }

    private func resolveKind(_ kind: String?) throws -> ChainKindFilter {
        guard let kind else { return .all }
        switch kind.lowercased() {
        case "all": return .all
        case "spec": return .spec
        case "sweep": return .sweep
        default:
            fputs("Error: invalid --kind '\(kind)'; valid values are: all, spec, sweep\n", stderr)
            throw ExitCode.failure
        }
    }
}
