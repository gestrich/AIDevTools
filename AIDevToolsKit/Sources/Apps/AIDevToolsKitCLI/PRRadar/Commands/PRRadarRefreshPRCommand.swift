import ArgumentParser
import Foundation
import PRRadarConfigService
import PRReviewFeature

struct PRRadarRefreshPRCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "refresh-pr",
        abstract: "Re-fetch PR data from GitHub (diff, comments, metadata)"
    )

    @OptionGroup var options: PRRadarCLIOptions

    func run() async throws {
        let config = try resolvePRRadarConfigFromOptions(options)
        let useCase = FetchPRUseCase(config: config)

        print("Refreshing PR #\(options.prNumber)...")

        var result: SyncSnapshot?

        for try await progress in useCase.execute(prNumber: options.prNumber, force: true) {
            switch progress {
            case .running:
                break
            case .progress:
                break
            case .log(let text):
                print(text, terminator: "")
            case .prepareOutput: break
            case .prepareToolUse: break
            case .taskEvent: break
            case .completed(let output):
                result = output
            case .failed(let error, let logs):
                if !logs.isEmpty {
                    printPRRadarError(logs)
                }
                throw PRRadarCLIError.phaseFailed("Refresh PR failed: \(error)")
            }
        }

        guard let output = result else {
            throw PRRadarCLIError.phaseFailed("Refresh PR produced no output")
        }

        print("\nRefresh complete:")
        print("  Files written: \(output.files.count)")
        print("  Issue comments: \(output.commentCount)")
        print("  Reviews: \(output.reviewCount)")
        print("  Inline review comments: \(output.reviewCommentCount)")
    }
}
