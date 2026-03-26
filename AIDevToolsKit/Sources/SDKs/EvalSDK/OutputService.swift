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

    // MARK: - Session Factory

    public static func makeSession(
        artifactsDirectory: URL,
        provider: String,
        caseId: String,
        client: (any AIClient)? = nil
    ) -> AIRunSession {
        let store = AIOutputStore(baseDirectory: artifactsDirectory.appendingPathComponent("raw"))
        let key = "\(provider)/\(caseId)"
        if let client {
            return AIRunSession(key: key, store: store, client: client)
        }
        return AIRunSession(key: key, store: store)
    }

    // MARK: - Writing

    public func writeArtifacts(
        result: ProviderResult,
        stderr: String,
        session: AIRunSession,
        configuration: RunConfiguration
    ) throws -> ProviderResult {
        var result = result

        result.rawStdoutPath = session.store.url(for: session.key)

        let stderrPath = configuration.artifactsDirectory
            .appendingPathComponent("raw")
            .appendingPathComponent(configuration.provider.rawValue)
            .appendingPathComponent("\(configuration.caseId).stderr")
        try FileManager.default.createDirectory(
            at: stderrPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try stderr.write(to: stderrPath, atomically: true, encoding: .utf8)
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
        let session = Self.makeSession(
            artifactsDirectory: artifactsDir,
            provider: provider.rawValue,
            caseId: caseId
        )

        guard let rawStdout = session.loadOutput() else {
            throw OutputServiceError.stdoutNotFound(session.store.url(for: session.key))
        }

        let mainOutput = format(rawStdout, provider: provider)

        let rubricSession = Self.makeSession(
            artifactsDirectory: artifactsDir,
            provider: provider.rawValue,
            caseId: "\(caseId).rubric"
        )
        var rubricOutput: String?
        if let rawRubric = rubricSession.loadOutput() {
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
