import AIOutputSDK
import ClaudeCLISDK
import CodexCLISDK
import EvalService
import Foundation

public struct OutputService: Sendable {

    public init() {}

    // MARK: - Paths

    static func artifactsDirectory(outputDirectory: URL) -> URL {
        outputDirectory.appendingPathComponent("artifacts")
    }

    static func providerDirectory(artifactsDirectory: URL, provider: String) -> URL {
        artifactsDirectory.appendingPathComponent(provider)
    }

    private static func outputStore(artifactsDirectory: URL) -> AIOutputStore {
        AIOutputStore(baseDirectory: artifactsDirectory.appendingPathComponent("raw"))
    }

    private static func stdoutKey(provider: String, caseId: String) -> String {
        "\(provider)/\(caseId)"
    }

    private static func stderrPath(artifactsDirectory: URL, provider: String, caseId: String) -> URL {
        artifactsDirectory
            .appendingPathComponent("raw")
            .appendingPathComponent(provider)
            .appendingPathComponent("\(caseId).stderr")
    }

    // MARK: - Writing

    public func write(
        result: ProviderResult,
        stdout: String,
        stderr: String,
        configuration: RunConfiguration
    ) throws -> ProviderResult {
        var result = result

        let store = Self.outputStore(artifactsDirectory: configuration.artifactsDirectory)
        let key = Self.stdoutKey(provider: configuration.provider.rawValue, caseId: configuration.caseId)
        try store.write(output: stdout, key: key)

        let stderrPath = Self.stderrPath(
            artifactsDirectory: configuration.artifactsDirectory,
            provider: configuration.provider.rawValue,
            caseId: configuration.caseId
        )
        try FileManager.default.createDirectory(
            at: stderrPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try stderr.write(to: stderrPath, atomically: true, encoding: .utf8)

        result.rawStdoutPath = store.url(for: key)
        result.rawStderrPath = stderrPath

        let providerDir = configuration.providerDirectory
        try FileManager.default.createDirectory(at: providerDir, withIntermediateDirectories: true)
        if let structured = result.structuredOutput {
            let outputFile = providerDir
                .appendingPathComponent("\(configuration.caseId).json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(structured).write(to: outputFile)
        }

        return result
    }

    public func writeSummary(
        _ summary: EvalSummary,
        artifactsDirectory: URL,
        provider: Provider
    ) throws {
        let providerDir = Self.providerDirectory(artifactsDirectory: artifactsDirectory, provider: provider.rawValue)
        try ArtifactWriter().writeSummary(summary, to: providerDir)
    }

    // MARK: - Reading

    public func readFormattedOutput(
        caseId: String,
        provider: Provider,
        outputDirectory: URL
    ) throws -> FormattedOutput {
        let artifactsDir = Self.artifactsDirectory(outputDirectory: outputDirectory)
        let store = Self.outputStore(artifactsDirectory: artifactsDir)
        let key = Self.stdoutKey(provider: provider.rawValue, caseId: caseId)

        guard let rawStdout = store.read(key: key) else {
            throw OutputServiceError.stdoutNotFound(store.url(for: key))
        }

        let mainOutput = format(rawStdout, provider: provider)

        let rubricKey = Self.stdoutKey(provider: provider.rawValue, caseId: "\(caseId).rubric")
        var rubricOutput: String?
        if let rawRubric = store.read(key: rubricKey) {
            rubricOutput = ClaudeStreamFormatter().format(rawRubric)
        }

        return FormattedOutput(mainOutput: mainOutput, rubricOutput: rubricOutput)
    }

    private func format(_ raw: String, provider: Provider) -> String {
        switch provider {
        case .claude:
            return ClaudeStreamFormatter().format(raw)
        case .codex:
            return CodexStreamFormatter().format(raw)
        }
    }
}

public struct FormattedOutput: Sendable {
    public let mainOutput: String
    public let rubricOutput: String?
}

public enum OutputServiceError: Error, LocalizedError {
    case stdoutNotFound(URL)

    public var errorDescription: String? {
        switch self {
        case .stdoutNotFound(let url):
            return "Raw stdout not found at \(url.path)"
        }
    }
}
