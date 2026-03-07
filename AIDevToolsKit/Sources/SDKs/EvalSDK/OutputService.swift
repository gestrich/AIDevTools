import Foundation
import ClaudeCLISDK
import CodexCLISDK
import EvalService

public struct OutputService: Sendable {

    public init() {}

    // MARK: - Paths

    static func artifactsDirectory(outputDirectory: URL) -> URL {
        outputDirectory.appendingPathComponent("artifacts")
    }

    static func rawDirectory(artifactsDirectory: URL, provider: String) -> URL {
        artifactsDirectory
            .appendingPathComponent("raw")
            .appendingPathComponent(provider)
    }

    static func rawDirectory(outputDirectory: URL, provider: String) -> URL {
        rawDirectory(
            artifactsDirectory: artifactsDirectory(outputDirectory: outputDirectory),
            provider: provider
        )
    }

    static func providerDirectory(artifactsDirectory: URL, provider: String) -> URL {
        artifactsDirectory.appendingPathComponent(provider)
    }

    static func stdoutPath(rawDirectory: URL, caseId: String) -> URL {
        rawDirectory.appendingPathComponent("\(caseId).stdout")
    }

    static func stderrPath(rawDirectory: URL, caseId: String) -> URL {
        rawDirectory.appendingPathComponent("\(caseId).stderr")
    }

    // MARK: - Writing

    public func write(
        result: ProviderResult,
        stdout: String,
        stderr: String,
        configuration: RunConfiguration
    ) throws -> ProviderResult {
        var result = result

        let rawDir = Self.rawDirectory(artifactsDirectory: configuration.artifactsDirectory, provider: configuration.provider.rawValue)
        try FileManager.default.createDirectory(at: rawDir, withIntermediateDirectories: true)

        let stdoutPath = Self.stdoutPath(rawDirectory: rawDir, caseId: configuration.caseId)
        let stderrPath = Self.stderrPath(rawDirectory: rawDir, caseId: configuration.caseId)
        try stdout.write(to: stdoutPath, atomically: true, encoding: .utf8)
        try stderr.write(to: stderrPath, atomically: true, encoding: .utf8)
        result.rawStdoutPath = stdoutPath
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
        let rawDir = Self.rawDirectory(outputDirectory: outputDirectory, provider: provider.rawValue)

        let stdoutPath = Self.stdoutPath(rawDirectory: rawDir, caseId: caseId)
        guard FileManager.default.fileExists(atPath: stdoutPath.path) else {
            throw OutputServiceError.stdoutNotFound(stdoutPath)
        }

        let rawStdout = try String(contentsOf: stdoutPath, encoding: .utf8)
        let mainOutput = format(rawStdout, provider: provider)

        let rubricStdoutPath = Self.stdoutPath(rawDirectory: rawDir, caseId: "\(caseId).rubric")
        var rubricOutput: String?
        if FileManager.default.fileExists(atPath: rubricStdoutPath.path) {
            let rawRubric = try String(contentsOf: rubricStdoutPath, encoding: .utf8)
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
