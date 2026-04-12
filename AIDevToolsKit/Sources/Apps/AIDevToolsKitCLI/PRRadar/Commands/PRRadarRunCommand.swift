import ArgumentParser
import Foundation
import PRRadarConfigService
import PRRadarModelsService
import PRReviewFeature

struct PRRadarRunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the full review pipeline (all phases)"
    )

    @OptionGroup var options: PRRadarCLIOptions

    @Option(name: .long, help: "Rule path name (uses the default rule path if omitted)")
    var rulesPathName: String?

    @Flag(name: .long, help: "Post comments without dry-run")
    var noDryRun: Bool = false

    @Option(name: .long, help: "Minimum violation score")
    var minScore: String?

    @Flag(name: .long, help: "Suppress AI output (show only status logs)")
    var quiet: Bool = false

    @Flag(name: .long, help: "Show full AI output including tool use events")
    var verbose: Bool = false

    @Option(name: .long, help: "Analysis mode: regex, script, ai, or all (default: all)")
    var mode: AnalysisMode = .all

    func run() async throws {
        let config = try resolvePRRadarConfigFromOptions(options)
        let useCase = RunPipelineUseCase(config: config)
        if !options.json {
            print("Running full pipeline for PR #\(options.prNumber)...")
        }

        var result: RunPipelineOutput?

        for try await progress in useCase.execute(
            prNumber: options.prNumber,
            rulesDir: try resolveRulesDir(rulesPathName: rulesPathName, config: config),
            noDryRun: noDryRun,
            minScore: minScore,
            analysisMode: mode
        ) {
            switch progress {
            case .running(let phase):
                if !options.json {
                    print("  Running \(phase.rawValue)...")
                }
            case .progress:
                break
            case .log(let text):
                if !options.json { print(text, terminator: "") }
            case .prepareStreamEvent(let event):
                switch event {
                case .textDelta(let text):
                    if !options.json && !quiet { printPRRadarAIOutput(text, verbose: verbose) }
                case .toolUse(let name, _):
                    if !options.json && !quiet && verbose { printPRRadarAIToolUse(name) }
                default:
                    break
                }
            case .taskEvent(_, let event):
                switch event {
                case .streamEvent(let event):
                    switch event {
                    case .textDelta(let text):
                        if !options.json && !quiet { printPRRadarAIOutput(text, verbose: verbose) }
                    case .toolUse(let name, _):
                        if !options.json && !quiet && verbose { printPRRadarAIToolUse(name) }
                    default:
                        break
                    }
                case .prompt, .completed:
                    break
                }
            case .completed(let output):
                result = output
            case .failed(let error, let logs):
                if !logs.isEmpty {
                    printPRRadarError(logs)
                }
                throw PRRadarCLIError.phaseFailed("Run failed: \(error)")
            }
        }

        guard let output = result else {
            throw PRRadarCLIError.phaseFailed("Run pipeline produced no output")
        }

        if options.json {
            var jsonOutput: [String: [String]] = [:]
            for (phase, files) in output.files {
                jsonOutput[phase.rawValue] = files
            }
            let data = try JSONSerialization.data(withJSONObject: jsonOutput, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("\nPipeline complete:")
            for phase in PRRadarPhase.allCases {
                if let files = output.files[phase] {
                    print("  \(phase.rawValue): \(files.count) files")
                }
            }
        }
    }
}
