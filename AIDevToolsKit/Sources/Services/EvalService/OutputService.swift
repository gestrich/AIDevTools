import AIOutputSDK
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

    public func writeEvalArtifacts(
        evalOutput: EvalRunOutput,
        provider: Provider,
        caseId: String,
        artifactsDirectory: URL
    ) throws -> ProviderResult {
        let sourceResult = evalOutput.result

        let rawDir = artifactsDirectory
            .appendingPathComponent("raw")
            .appendingPathComponent(provider.rawValue)
        try FileManager.default.createDirectory(at: rawDir, withIntermediateDirectories: true)

        let stdoutPath = rawDir.appendingPathComponent("\(caseId).stdout")
        try evalOutput.rawStdout.write(to: stdoutPath, atomically: true, encoding: .utf8)

        let stderrPath = rawDir.appendingPathComponent("\(caseId).stderr")
        try evalOutput.stderr.write(to: stderrPath, atomically: true, encoding: .utf8)

        let providerDir = Self.providerDirectory(artifactsDirectory: artifactsDirectory, provider: provider.rawValue)
        try FileManager.default.createDirectory(at: providerDir, withIntermediateDirectories: true)
        if let structured = sourceResult.structuredOutput {
            let outputFile = providerDir.appendingPathComponent("\(caseId).json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(structured).write(to: outputFile)
        }

        return ProviderResult(
            provider: sourceResult.provider,
            structuredOutput: sourceResult.structuredOutput,
            resultText: sourceResult.resultText,
            events: sourceResult.events,
            toolEvents: sourceResult.toolEvents,
            metrics: sourceResult.metrics,
            rawStdoutPath: stdoutPath,
            rawStderrPath: stderrPath,
            rawTracePath: sourceResult.rawTracePath,
            error: sourceResult.error,
            toolCallSummary: sourceResult.toolCallSummary
        )
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
        outputDirectory: URL,
        formatter: any StreamFormatter,
        rubricFormatter: any StreamFormatter
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

        let mainOutput = formatter.format(rawStdout)

        let rubricSession = Self.makeSession(
            artifactsDirectory: artifactsDir,
            provider: provider.rawValue,
            caseId: "\(caseId).rubric"
        )
        var rubricOutput: String?
        if let rawRubric = rubricSession.loadOutput() {
            rubricOutput = rubricFormatter.format(rawRubric)
        }

        return FormattedOutput(mainOutput: mainOutput, rubricOutput: rubricOutput)
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
