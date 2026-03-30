import ArgumentParser
import Foundation
import PRRadarConfigService
import PRRadarModelsService
import PRReviewFeature

struct PRRadarViolationsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "violations",
        abstract: "List pending review violations for a PR"
    )

    @OptionGroup var options: PRRadarCLIOptions

    @Option(name: .long, help: "Minimum violation score to include")
    var minScore: Int = 5

    @Flag(name: .long, help: "Refresh comments from GitHub before listing")
    var refresh: Bool = false

    func run() async throws {
        let config = try resolvePRRadarConfigFromOptions(options)
        let useCase = FetchReviewCommentsUseCase(config: config)

        let comments = try await useCase.execute(
            prNumber: options.prNumber,
            minScore: minScore,
            commitHash: options.commit,
            cachedOnly: !refresh
        )

        let pending = comments.filter(\.readyForPosting)

        if options.json {
            let encoded = pending.map { comment in
                var obj: [String: Any] = [
                    "file": comment.filePath,
                    "state": comment.state.description,
                ]
                if let line = comment.lineNumber { obj["line"] = line }
                if let score = comment.score { obj["score"] = score }
                if let rule = comment.ruleName { obj["rule"] = rule }
                if let body = comment.pending?.comment {
                    obj["body"] = String(body.prefix(200))
                }
                return obj
            }
            let data = try JSONSerialization.data(withJSONObject: encoded, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)
        } else {
            if pending.isEmpty {
                print("No pending violations for PR #\(options.prNumber).")
            } else {
                print("Pending violations for PR #\(options.prNumber) (min score \(minScore)):\n")
                for comment in pending {
                    let scoreStr = comment.score.map { " [score: \($0)]" } ?? ""
                    let lineStr = comment.lineNumber.map { ":\($0)" } ?? ""
                    let rule = comment.ruleName.map { " (\($0))" } ?? ""
                    print("  \(comment.filePath)\(lineStr)\(rule)\(scoreStr)")
                }
                print("\n\(pending.count) violation(s) ready to post.")
            }
        }
    }
}

extension ReviewComment.State {
    var description: String {
        switch self {
        case .new: "new"
        case .redetected: "redetected"
        case .needsUpdate: "needs-update"
        case .postedOnly: "posted-only"
        }
    }
}
