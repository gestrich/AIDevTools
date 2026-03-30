import Foundation

public enum GitHubServiceError: Error, LocalizedError {
    case cannotParseRemoteURL(String)
    case missingToken

    public var errorDescription: String? {
        switch self {
        case .cannotParseRemoteURL(let url):
            return "Cannot parse owner/repo from git remote URL: \(url)"
        case .missingToken:
            return "No GitHub token found. Set GITHUB_TOKEN env var, add to .env file, or store credentials in the Keychain via 'config credentials add'."
        }
    }
}
