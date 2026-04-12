import ArgumentParser
import Foundation
import PRRadarConfigService
import PRRadarModelsService
import PRReviewFeature

struct PRRadarRefreshCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "refresh",
        abstract: "Fetch recent PRs from GitHub"
    )

    @OptionGroup var filterOptions: PRRadarFilterOptions

    @Option(name: .long, help: "Repository name (from repos list)")
    var config: String?

    @Flag(name: .long, help: "Output results as JSON")
    var json: Bool = false

    func run() async throws {
        let prRadarConfig = try resolvePRRadarConfig(repoName: config)
        let prFilter = try filterOptions.buildFilter(config: prRadarConfig)

        let useCase = FetchPRsUseCase(config: prRadarConfig)

        if !json {
            print("Fetching recent PRs from GitHub...")
        }
        for try await progress in useCase.execute(filter: prFilter) {
            switch progress {
            case .running:
                break
            case .progress:
                break
            case .log(let text):
                if !json { print(text, terminator: "") }
            case .prepareOutput: break
            case .prepareToolUse: break
            case .taskEvent: break
            case .completed(let result):
                let prs = result.prList
                if json {
                    let encoded = prs.map { pr in
                        [
                            "number": pr.number,
                            "title": pr.title,
                            "author": pr.author.login,
                            "state": pr.state,
                            "branch": pr.headRefName,
                            "baseBranch": pr.baseRefName as Any,
                        ] as [String: Any]
                    }
                    let data = try JSONSerialization.data(withJSONObject: encoded, options: [.prettyPrinted, .sortedKeys])
                    print(String(data: data, encoding: .utf8)!)
                } else {
                    print("\nFetched \(prs.count) PRs:")
                    for pr in prs {
                        print("  #\(pr.number) \(pr.title) (\(pr.author.login))")
                    }
                }
            case .failed(let error, let logs):
                if !logs.isEmpty { printPRRadarError(logs) }
                throw PRRadarCLIError.phaseFailed("Refresh failed: \(error)")
            }
        }
    }
}
