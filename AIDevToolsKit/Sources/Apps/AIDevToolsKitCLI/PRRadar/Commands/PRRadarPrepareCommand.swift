import ArgumentParser
import ClaudeCLISDK
import Foundation
import PRRadarConfigService
import PRReviewFeature

struct PRRadarPrepareCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prepare",
        abstract: "Prepare evaluation tasks (Phase 2)"
    )

    @OptionGroup var options: PRRadarCLIOptions

    @Option(name: .long, help: "Rule path name (uses the default rule path if omitted)")
    var rulesPathName: String?

    @Flag(name: .long, help: "Suppress AI output (show only status logs)")
    var quiet: Bool = false

    @Flag(name: .long, help: "Show full AI output including tool use events")
    var verbose: Bool = false

    func run() async throws {
        let config = try resolvePRRadarConfigFromOptions(options)
        let useCase = PrepareUseCase(config: config, aiClient: ClaudeProvider())
        if !options.json {
            print("Preparing evaluation tasks for PR #\(options.prNumber)...")
        }

        var result: PrepareOutput?

        let resolvedRules = try resolveRulesDir(rulesPathName: rulesPathName, config: config)
        for try await progress in useCase.execute(prNumber: options.prNumber, rulesDir: resolvedRules, commitHash: options.commit) {
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
            case .taskEvent: break
            case .completed(let output):
                result = output
            case .failed(let error, let logs):
                if !logs.isEmpty {
                    printPRRadarError(logs)
                }
                throw PRRadarCLIError.phaseFailed("Prepare failed: \(error)")
            }
        }

        guard let output = result else {
            throw PRRadarCLIError.phaseFailed("Prepare phase produced no output")
        }

        if options.json {
            let jsonOutput = PrepareJSONOutput(
                focusAreas: output.focusAreas.count,
                rules: output.rules.count,
                tasks: output.tasks.count
            )
            let data = try JSONEncoder.prRadarPrettyEncoder.encode(jsonOutput)
            guard let json = String(data: data, encoding: .utf8) else {
                throw PRRadarCLIError.phaseFailed("Failed to encode output as UTF-8")
            }
            print(json)
        } else {
            print("\nPrepare complete:")
            print("  Focus areas: \(output.focusAreas.count)")
            print("  Rules loaded: \(output.rules.count)")
            print("  Evaluation tasks: \(output.tasks.count)")

            if !output.focusAreas.isEmpty {
                print("\nFocus areas:")
                for area in output.focusAreas {
                    print("  [\(area.focusType.rawValue)] \(area.filePath):\(area.startLine)-\(area.endLine)")
                    print("    \(area.description)")
                }
            }

            if !output.rules.isEmpty {
                print("\nRules:")
                for rule in output.rules {
                    print("  [\(rule.category)] \(rule.name)")
                }
            }
        }
    }
}

private struct PrepareJSONOutput: Encodable {
    let focusAreas: Int
    let rules: Int
    let tasks: Int

    enum CodingKeys: String, CodingKey {
        case focusAreas = "focus_areas"
        case rules
        case tasks
    }
}
