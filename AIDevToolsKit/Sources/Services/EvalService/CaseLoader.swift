import Foundation

public struct CaseLoader: Sendable {

    public init() {}

    public func loadCases(from casesDirectory: URL) throws -> [EvalCase] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: casesDirectory.path) else {
            throw CaseLoaderError.directoryNotFound(casesDirectory.path)
        }

        let contents = try fileManager.contentsOfDirectory(
            at: casesDirectory,
            includingPropertiesForKeys: nil
        )
        let jsonlFiles = contents
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var cases: [EvalCase] = []
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        for file in jsonlFiles {
            let suite = file.deletingPathExtension().lastPathComponent
            let text = try String(contentsOf: file, encoding: .utf8)

            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                guard let data = trimmed.data(using: .utf8) else { continue }

                var evalCase = try decoder.decode(EvalCase.self, from: data)
                evalCase.suite = suite
                cases.append(evalCase)
            }
        }

        return cases
    }

    public func filterCases(
        _ cases: [EvalCase],
        caseId: String? = nil,
        skill: String? = nil,
        suite: String? = nil
    ) -> [EvalCase] {
        var filtered = cases
        if let suite {
            filtered = filtered.filter { $0.suite == suite }
        }
        if let caseId {
            filtered = filtered.filter { $0.id == caseId }
        }
        if let skill {
            filtered = filtered.filter { evalCase in
                evalCase.skills?.contains { $0.skill == skill } ?? false
            }
        }
        return filtered
    }
}

public enum CaseLoaderError: Error, LocalizedError {
    case directoryNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .directoryNotFound(let path):
            return "Cases directory not found: \(path)"
        }
    }
}
