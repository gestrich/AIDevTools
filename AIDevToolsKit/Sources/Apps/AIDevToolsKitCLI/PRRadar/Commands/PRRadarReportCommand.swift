import ArgumentParser
import Foundation
import PRRadarConfigService
import PRReviewFeature

struct PRRadarReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Generate summary report (Phase 4)"
    )

    @OptionGroup var options: PRRadarCLIOptions

    @Option(name: .long, help: "Minimum violation score to include")
    var minScore: String?

    func run() async throws {
        let config = try resolvePRRadarConfigFromOptions(options)
        let useCase = GenerateReportUseCase(config: config)

        if !options.json {
            print("Generating report for PR #\(options.prNumber)...")
        }

        var result: ReportPhaseOutput?

        for try await progress in useCase.execute(prNumber: options.prNumber, minScore: minScore, commitHash: options.commit) {
            switch progress {
            case .running:
                break
            case .progress:
                break
            case .log(let text):
                if !options.json { print(text, terminator: "") }
            case .prepareStreamEvent: break
            case .taskEvent: break
            case .completed(let output):
                result = output
            case .failed(let error, let logs):
                if !logs.isEmpty {
                    printPRRadarError(logs)
                }
                throw PRRadarCLIError.phaseFailed("Report failed: \(error)")
            }
        }

        guard let output = result else {
            throw PRRadarCLIError.phaseFailed("Report phase produced no output")
        }

        if options.json {
            let data = try JSONEncoder.prRadarPrettyEncoder.encode(output.report)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print(output.markdownContent)
        }
    }
}
