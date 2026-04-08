import ArgumentParser
import DataPathsService
import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModelsService
import PRReviewFeature
import RepositorySDK
import SettingsService

struct PRRadarCLIOptions: ParsableArguments {
    @Argument(help: "Pull request number")
    var prNumber: Int

    @Option(name: .long, help: "Repository name (from repos list)")
    var config: String?

    @Option(name: .long, help: "Commit hash to target (defaults to latest)")
    var commit: String?

    @Option(name: .long, help: "Diff source: 'git' (local git history) or 'github-api' (GitHub REST API)")
    var diffSource: DiffSource?

    @Option(name: .long, help: "GitHub token (overrides all other credential sources)")
    var githubToken: String?

    @Flag(name: .long, help: "Output results as JSON")
    var json: Bool = false
}

extension DiffSource: ExpressibleByArgument {}
extension AnalysisMode: ExpressibleByArgument {}

enum PRRadarCLIError: Error, CustomStringConvertible {
    case phaseFailed(String)
    case repoNotFound(String)

    var description: String {
        switch self {
        case .phaseFailed(let message):
            return message
        case .repoNotFound(let name):
            return "Repository '\(name)' not found. Use 'repos list' to see available repositories."
        }
    }
}

func resolvePRRadarConfig(repoName: String?, diffSource: DiffSource? = nil, githubToken: String? = nil) throws -> PRRadarRepoConfig {
    let dataPathsService = try DataPathsService.fromCLI(dataPath: nil)
    let settingsService = try SettingsService(dataPathsService: dataPathsService)
    let repos = try settingsService.loadRepositories()

    let repo: RepositoryConfiguration
    if let repoName {
        guard let found = repos.first(where: { $0.name == repoName }) else {
            throw PRRadarCLIError.repoNotFound(repoName)
        }
        repo = found
    } else {
        guard let first = repos.first else {
            throw PRRadarCLIError.repoNotFound("(none configured — use 'repos add' to add a repository)")
        }
        repo = first
    }

    let settings = repo.prradar ?? PRRadarRepoSettings()

    let outputDir = try dataPathsService.path(for: .prradarOutput(repo.name))
    let outputDirString = outputDir.path(percentEncoded: false)

    var config = PRRadarRepoConfig.make(
        from: repo,
        settings: settings,
        outputDir: outputDirString,
        agentScriptPath: settings.agentScriptPath,
        dataRootURL: dataPathsService.rootPath,
        explicitToken: githubToken
    )

    if let diffSource {
        config = PRRadarRepoConfig(
            id: config.id,
            name: config.name,
            repoPath: config.repoPath,
            outputDir: config.outputDir,
            rulePaths: config.rulePaths,
            agentScriptPath: config.agentScriptPath,
            githubAccount: config.githubAccount,
            diffSource: diffSource,
            defaultBaseBranch: config.defaultBaseBranch,
            dataRootURL: config.dataRootURL,
            explicitToken: config.explicitToken
        )
    }

    return config
}

func resolvePRRadarConfigFromOptions(_ options: PRRadarCLIOptions) throws -> PRRadarRepoConfig {
    try resolvePRRadarConfig(repoName: options.config, diffSource: options.diffSource, githubToken: options.githubToken)
}

func resolveRulesDir(rulesPathName: String?, config: PRRadarRepoConfig) throws -> String {
    guard let rulesPathName else {
        return config.resolvedDefaultRulesDir
    }
    guard let resolved = config.resolvedRulesDir(named: rulesPathName) else {
        let available = config.rulePaths.map(\.name).joined(separator: ", ")
        throw ValidationError("Rule path '\(rulesPathName)' not found. Available: \(available)")
    }
    return resolved
}

func parsePRRadarDateString(_ value: String) -> Date? {
    ISO8601DateFormatter().date(from: value + "T00:00:00Z")
}

func parsePRRadarStateFilter(_ value: String?) throws -> PRState? {
    guard let value else { return nil }
    if value.lowercased() == "all" { return nil }
    guard let parsed = PRState.fromCLIString(value) else {
        throw ValidationError("Invalid state '\(value)'. Valid values: open, draft, closed, merged, all")
    }
    return parsed
}

func printPRRadarError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func printPRRadarAIOutput(_ text: String, verbose: Bool) {
    for line in text.components(separatedBy: "\n") {
        if verbose {
            print("    \(line)")
        } else {
            print("    [AI] \(line)")
        }
    }
}

func printPRRadarAIToolUse(_ name: String) {
    print("    [AI] \u{001B}[36m[tool: \(name)]\u{001B}[0m")
}

func prRadarSeverityColor(_ score: Int) -> String {
    switch score {
    case 1...4: return "\u{001B}[32m"
    case 5...7: return "\u{001B}[33m"
    default: return "\u{001B}[31m"
    }
}

extension JSONEncoder {
    static let prRadarPrettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
