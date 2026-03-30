import EnvironmentSDK
import Foundation
import PRRadarModelsService

public enum PRDiscoveryService {

    // MARK: - Discovery

    /// Discover PRs from the shared GitHub cache directory.
    public static func discoverPRs(gitHubCacheURL: URL) -> [PRMetadata] {
        let fileManager = FileManager.default
        let path = gitHubCacheURL.path(percentEncoded: false)

        guard fileManager.fileExists(atPath: path),
              let contents = try? fileManager.contentsOfDirectory(atPath: path)
        else {
            return []
        }

        let prs: [PRMetadata] = contents.compactMap { dirName in
            guard let prNumber = Int(dirName) else { return nil }
            guard let ghPR = loadGitHubPR(gitHubCacheURL: gitHubCacheURL, prNumber: prNumber),
                  let metadata = try? ghPR.toPRMetadata() else { return nil }
            return metadata
        }

        return prs.sorted { $0.number > $1.number }
    }

    /// Discover PRs using the shared GitHub cache path from the repository configuration.
    public static func discoverPRs(config: RepositoryConfiguration) -> [PRMetadata] {
        guard let cacheURL = config.gitHubCacheURL else { return [] }
        return discoverPRs(gitHubCacheURL: cacheURL)
    }

    /// Discover a single PR using the appropriate path from the repository configuration.
    public static func discoverPR(number: Int, config: RepositoryConfiguration) -> PRMetadata? {
        discoverPRs(config: config).first(where: { $0.number == number })
    }

    // MARK: - Load from GitHub cache

    /// Load a PR from the shared GitHub cache directory.
    public static func loadGitHubPR(gitHubCacheURL: URL, prNumber: Int) -> GitHubPullRequest? {
        let url = gitHubCacheURL.appendingPathComponent("\(prNumber)/gh-pr.json")
        guard let data = FileManager.default.contents(atPath: url.path(percentEncoded: false)) else { return nil }
        return try? JSONDecoder().decode(GitHubPullRequest.self, from: data)
    }

    /// Load a PR using the shared GitHub cache path from the repository configuration.
    public static func loadGitHubPR(config: RepositoryConfiguration, prNumber: Int) -> GitHubPullRequest? {
        guard let cacheURL = config.gitHubCacheURL else { return nil }
        return loadGitHubPR(gitHubCacheURL: cacheURL, prNumber: prNumber)
    }

    /// Load PR comments from the shared GitHub cache directory.
    public static func loadComments(gitHubCacheURL: URL, prNumber: Int) -> GitHubPullRequestComments? {
        let url = gitHubCacheURL.appendingPathComponent("\(prNumber)/gh-comments.json")
        guard let data = FileManager.default.contents(atPath: url.path(percentEncoded: false)) else { return nil }
        return try? JSONDecoder().decode(GitHubPullRequestComments.self, from: data)
    }

    /// Load PR comments using the shared GitHub cache path from the repository configuration.
    public static func loadComments(config: RepositoryConfiguration, prNumber: Int) -> GitHubPullRequestComments? {
        guard let cacheURL = config.gitHubCacheURL else { return nil }
        return loadComments(gitHubCacheURL: cacheURL, prNumber: prNumber)
    }

    // MARK: - Repo slug helpers

    public static func repoSlug(fromRepoPath repoPath: String) -> String? {
        let gitConfigPath = "\(repoPath)/.git/config"
        guard let content = try? String(contentsOfFile: gitConfigPath, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: .newlines)
        var inOriginSection = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[remote \"origin\"]" {
                inOriginSection = true
                continue
            }
            if trimmed.hasPrefix("[") {
                inOriginSection = false
                continue
            }
            if inOriginSection, trimmed.hasPrefix("url = ") {
                let url = String(trimmed.dropFirst("url = ".count))
                return slugFromRemoteURL(url)
            }
        }
        return nil
    }

    private static func slugFromRemoteURL(_ remoteURL: String) -> String? {
        // HTTPS: https://github.com/owner/repo.git
        if let range = remoteURL.range(of: "github.com/") {
            var slug = String(remoteURL[range.upperBound...])
            if slug.hasSuffix(".git") { slug = String(slug.dropLast(4)) }
            return slug.isEmpty ? nil : slug
        }
        // SSH: git@github.com:owner/repo.git
        if let range = remoteURL.range(of: "github.com:") {
            var slug = String(remoteURL[range.upperBound...])
            if slug.hasSuffix(".git") { slug = String(slug.dropLast(4)) }
            return slug.isEmpty ? nil : slug
        }
        return nil
    }
}
