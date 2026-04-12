import ArgumentParser
import Foundation
import PRRadarConfigService
import PRReviewFeature

struct PRRadarPostCommentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "post-comment",
        abstract: "Post a manual inline comment on a PR"
    )

    @OptionGroup var options: PRRadarCLIOptions

    @Option(name: .long, help: "File path in the PR diff")
    var file: String

    @Option(name: .long, help: "Line number in the new file")
    var line: Int

    @Option(name: .long, help: "Comment body text")
    var body: String

    func run() async throws {
        let config = try resolvePRRadarConfigFromOptions(options)

        let resolvedCommitSHA: String?
        if let hash = options.commit {
            resolvedCommitSHA = hash
        } else {
            resolvedCommitSHA = await FetchPRUseCase.resolveCommitHash(config: config, prNumber: options.prNumber)
        }
        guard let commitSHA = resolvedCommitSHA else {
            throw PRRadarCLIError.phaseFailed("Could not resolve commit SHA. Use --commit to specify one, or run 'sync' first.")
        }

        print("Posting comment on PR #\(options.prNumber) at \(file):\(line)...")

        let useCase = PostManualCommentUseCase(config: config)
        let success = try await useCase.execute(
            prNumber: options.prNumber,
            filePath: file,
            lineNumber: line,
            body: body,
            commitSHA: commitSHA
        )

        if success {
            print("Comment posted successfully.")
        } else {
            throw PRRadarCLIError.phaseFailed("Failed to post comment.")
        }
    }
}
