import ArgumentParser
import Foundation
import PRRadarConfigService
import PRReviewFeature

struct PRRadarRefreshPRCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "refresh-pr",
        abstract: "Re-fetch PR metadata from GitHub (comments, reviews, check runs)"
    )

    @OptionGroup var options: PRRadarCLIOptions

    func run() async throws {
        let config = try resolvePRRadarConfigFromOptions(options)
        let useCase = GitHubPRLoaderUseCase(config: config)

        print("Refreshing PR #\(options.prNumber)...")

        var fetchError: String?

        for await event in useCase.execute(prNumber: options.prNumber) {
            switch event {
            case .prFetchStarted(let prNumber):
                print("Enriching PR #\(prNumber)...")
            case .prUpdated(let metadata):
                print("  #\(metadata.number) \(metadata.title)")
            case .prFetchFailed(let prNumber, let error):
                printPRRadarError("Failed PR #\(prNumber): \(error)")
                fetchError = error
            case .completed:
                print("Done.")
            default:
                break
            }
        }

        if let error = fetchError {
            throw PRRadarCLIError.phaseFailed("Refresh PR failed: \(error)")
        }
    }
}
