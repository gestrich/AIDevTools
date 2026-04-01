import EnvironmentSDK
import Foundation
import PRRadarModelsService

public enum PRDiscoveryService {

    // MARK: - Discovery

    /// Discover PRs from the shared GitHub cache directory. Performs disk I/O on a background thread.
    public static func discoverPRs(gitHubCacheURL: URL) async -> [PRMetadata] {
        await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let path = gitHubCacheURL.path(percentEncoded: false)

            guard fileManager.fileExists(atPath: path),
                  let contents = try? fileManager.contentsOfDirectory(atPath: path)
            else {
                return []
            }

            let prs: [PRMetadata] = contents.compactMap { dirName in
                guard let prNumber = Int(dirName) else { return nil }
                guard let ghPR = loadGitHubPRSync(gitHubCacheURL: gitHubCacheURL, prNumber: prNumber),
                      let metadata = try? ghPR.toPRMetadata() else { return nil }
                return metadata
            }

            return prs.sorted { $0.number > $1.number }
        }.value
    }

    /// Discover PRs using the shared GitHub cache path from the repository configuration.
    public static func discoverPRs(config: PRRadarRepoConfig) async -> [PRMetadata] {
        guard let cacheURL = config.gitHubCacheURL else { return [] }
        return await discoverPRs(gitHubCacheURL: cacheURL)
    }

    /// Load a single PR's metadata directly from the cache without scanning all directories.
    public static func discoverPR(number: Int, config: PRRadarRepoConfig) async -> PRMetadata? {
        guard let cacheURL = config.gitHubCacheURL else { return nil }
        return await Task.detached(priority: .userInitiated) {
            guard let ghPR = loadGitHubPRSync(gitHubCacheURL: cacheURL, prNumber: number),
                  let metadata = try? ghPR.toPRMetadata() else { return nil }
            return metadata
        }.value
    }

    // MARK: - Load from GitHub cache

    /// Load a PR from the shared GitHub cache directory. Performs disk I/O on a background thread.
    public static func loadGitHubPR(gitHubCacheURL: URL, prNumber: Int) async -> GitHubPullRequest? {
        await Task.detached(priority: .userInitiated) {
            loadGitHubPRSync(gitHubCacheURL: gitHubCacheURL, prNumber: prNumber)
        }.value
    }

    /// Load a PR using the shared GitHub cache path from the repository configuration.
    public static func loadGitHubPR(config: PRRadarRepoConfig, prNumber: Int) async -> GitHubPullRequest? {
        guard let cacheURL = config.gitHubCacheURL else { return nil }
        return await loadGitHubPR(gitHubCacheURL: cacheURL, prNumber: prNumber)
    }

    /// Load PR comments from the shared GitHub cache directory. Performs disk I/O on a background thread.
    public static func loadComments(gitHubCacheURL: URL, prNumber: Int) async -> GitHubPullRequestComments? {
        await Task.detached(priority: .userInitiated) {
            loadCommentsSync(gitHubCacheURL: gitHubCacheURL, prNumber: prNumber)
        }.value
    }

    /// Load PR comments using the shared GitHub cache path from the repository configuration.
    public static func loadComments(config: PRRadarRepoConfig, prNumber: Int) async -> GitHubPullRequestComments? {
        guard let cacheURL = config.gitHubCacheURL else { return nil }
        return await loadComments(gitHubCacheURL: cacheURL, prNumber: prNumber)
    }

    // MARK: - Sync helpers (for use inside Task.detached blocks)

    static func loadGitHubPRSync(gitHubCacheURL: URL, prNumber: Int) -> GitHubPullRequest? {
        let url = gitHubCacheURL.appendingPathComponent("\(prNumber)/gh-pr.json")
        guard let data = FileManager.default.contents(atPath: url.path(percentEncoded: false)) else { return nil }
        return try? JSONDecoder().decode(GitHubPullRequest.self, from: data)
    }

    static func loadCommentsSync(gitHubCacheURL: URL, prNumber: Int) -> GitHubPullRequestComments? {
        let url = gitHubCacheURL.appendingPathComponent("\(prNumber)/gh-comments.json")
        guard let data = FileManager.default.contents(atPath: url.path(percentEncoded: false)) else { return nil }
        return try? JSONDecoder().decode(GitHubPullRequestComments.self, from: data)
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
