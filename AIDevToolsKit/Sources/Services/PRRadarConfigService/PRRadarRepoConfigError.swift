import Foundation

public enum PRRadarRepoConfigError: LocalizedError {
    case noDataRoot

    public var errorDescription: String? {
        "GitHub cache URL not configured; ensure dataRootURL is set on PRRadarRepoConfig"
    }
}
