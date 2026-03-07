import Foundation

public struct ArtifactWriter: Sendable {

    public init() {}

    public func writeArtifact(
        data: Data,
        to directory: URL,
        filename: String
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(filename)
        try data.write(to: fileURL)
    }

    public func writeJSON(_ value: some Encodable, to directory: URL, filename: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try writeArtifact(data: data, to: directory, filename: filename)
    }

    public func writeText(_ text: String, to directory: URL, filename: String) throws {
        guard let data = text.data(using: .utf8) else { return }
        try writeArtifact(data: data, to: directory, filename: filename)
    }

    public func writeSummary(_ summary: EvalSummary, to artifactsDirectory: URL) throws {
        try writeJSON(summary, to: artifactsDirectory, filename: "summary.json")
    }

    public func writeTrace(
        content: String,
        caseId: String,
        to tracesDirectory: URL
    ) throws {
        try writeText(content, to: tracesDirectory, filename: "\(caseId).jsonl")
    }
}
