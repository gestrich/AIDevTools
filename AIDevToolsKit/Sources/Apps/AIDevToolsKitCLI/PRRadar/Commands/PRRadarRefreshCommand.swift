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

        let useCase = GitHubPRLoaderUseCase(config: prRadarConfig)
        var finalPRs: [PRMetadata] = []

        for await event in useCase.execute(filter: prFilter) {
            switch event {
            case .listLoadStarted:
                if !json { print("Loading cached PRs...") }
            case .cached(let prs):
                if !json { print("Loaded \(prs.count) PRs from cache") }
                finalPRs = prs
            case .listFetchStarted:
                if !json { print("Fetching from GitHub...") }
            case .fetched(let prs):
                if !json { print("Fetched \(prs.count) PRs") }
                finalPRs = prs
            case .listFetchFailed(let message):
                printPRRadarError("List fetch failed: \(message)")
            case .prFetchStarted(let prNumber):
                if !json { print("Enriching PR #\(prNumber)...") }
            case .prUpdated(let metadata):
                if !json { print("  #\(metadata.number) \(metadata.title)") }
                if let index = finalPRs.firstIndex(where: { $0.number == metadata.number }) {
                    finalPRs[index] = metadata
                }
            case .prFetchFailed(let prNumber, let error):
                printPRRadarError("Failed PR #\(prNumber): \(error)")
            case .completed:
                if !json { print("Done.") }
            }
        }

        if json {
            let encoded = finalPRs.map { pr in
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
            print(String(data: data, encoding: .utf8) ?? "")
        }
    }
}
