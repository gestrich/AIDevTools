import ArgumentParser
import Foundation
import GitHubService
import PRRadarConfigService
import PRRadarModelsService

private struct PRListOutput: Encodable {
    let author: String
    let baseBranch: String
    let branch: String
    let number: Int
    let state: String
    let title: String
}

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
        let gitHubConfig = try prRadarConfig.makeGitHubRepoConfig()

        let useCase = GitHubPRLoaderUseCase(config: gitHubConfig)
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
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let items = finalPRs.map { pr in
                PRListOutput(
                    author: pr.author.login,
                    baseBranch: pr.baseRefName,
                    branch: pr.headRefName,
                    number: pr.number,
                    state: pr.state,
                    title: pr.title
                )
            }
            let data = try encoder.encode(items)
            print(String(data: data, encoding: .utf8) ?? "")
        }
    }
}
