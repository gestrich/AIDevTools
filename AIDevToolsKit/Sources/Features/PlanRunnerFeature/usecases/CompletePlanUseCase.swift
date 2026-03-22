import Foundation

public struct CompletePlanUseCase: Sendable {

    public enum CompletionError: Error, LocalizedError {
        case notFound(String)
        case destinationExists(String)

        public var errorDescription: String? {
            switch self {
            case .notFound(let path):
                return "Plan file not found: \(path)"
            case .destinationExists(let path):
                return "A file already exists at: \(path)"
            }
        }
    }

    public init() {}

    /// Moves a plan file from the proposed directory to the completed directory.
    /// - Parameters:
    ///   - planURL: Path to the plan file in the proposed directory
    ///   - completedDirectory: Path to the completed directory
    /// - Returns: The URL of the moved file in the completed directory
    @discardableResult
    public func run(planURL: URL, completedDirectory: URL) throws -> URL {
        let fm = FileManager.default

        guard fm.fileExists(atPath: planURL.path) else {
            throw CompletionError.notFound(planURL.path)
        }

        if !fm.fileExists(atPath: completedDirectory.path) {
            try fm.createDirectory(at: completedDirectory, withIntermediateDirectories: true)
        }

        let destination = completedDirectory.appendingPathComponent(planURL.lastPathComponent)

        guard !fm.fileExists(atPath: destination.path) else {
            throw CompletionError.destinationExists(destination.path)
        }

        try fm.moveItem(at: planURL, to: destination)
        return destination
    }
}
