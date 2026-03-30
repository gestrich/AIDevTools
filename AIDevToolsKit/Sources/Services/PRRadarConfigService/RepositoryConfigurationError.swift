import Foundation

public enum RepositoryConfigurationError: LocalizedError {
    case noDataRoot

    public var errorDescription: String? {
        "GitHub cache URL not configured; ensure dataRootURL is set on RepositoryConfiguration"
    }
}
