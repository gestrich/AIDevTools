import EnvironmentSDK
import Foundation
import PRRadarModelsService

public enum PRDiscoveryService {

    // MARK: - Discovery

    public static func discoverPRs(outputDir: String, repoSlug: String? = nil) -> [PRMetadata] {
        let fileManager = FileManager.default
        let expandedPath = PathUtilities.expandTilde(outputDir)

        guard fileManager.fileExists(atPath: expandedPath),
              let contents = try? fileManager.contentsOfDirectory(atPath: expandedPath)
        else {
            return []
        }

        let prs: [PRMetadata] = contents.compactMap { dirName in
            guard let prNumber = Int(dirName) else { return nil }

            let metadata: PRMetadata
            if let ghPR = loadGitHubPR(outputDir: expandedPath, prNumber: prNumber),
               let converted = try? ghPR.toPRMetadata() {
                metadata = converted
            } else {
                let ghPRPath = PRRadarPhasePaths.ghPRFilePath(outputDir: expandedPath, prNumber: prNumber)
                if let data = fileManager.contents(atPath: ghPRPath),
                   let prMeta = try? JSONDecoder().decode(PRMetadata.self, from: data) {
                    metadata = prMeta
                } else {
                    return repoSlug == nil ? PRMetadata.fallback(number: prNumber) : nil
                }
            }

            if let repoSlug {
                let metadataDir = PRRadarPhasePaths.metadataDirectory(outputDir: expandedPath, prNumber: prNumber)
                let ghRepoPath = "\(metadataDir)/gh-repo.json"
                guard let repoData = fileManager.contents(atPath: ghRepoPath),
                      let repoJSON = try? JSONSerialization.jsonObject(with: repoData) as? [String: Any],
                      let owner = (repoJSON["owner"] as? [String: Any])?["login"] as? String,
                      let name = repoJSON["name"] as? String,
                      "\(owner)/\(name)" == repoSlug
                else {
                    return nil
                }
            }

            return metadata
        }

        return prs.sorted { $0.number > $1.number }
    }

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

    /// Discover PRs using the appropriate path from the repository configuration.
    ///
    /// Uses the shared GitHub cache when available; falls back to the legacy PRRadar output path.
    public static func discoverPRs(config: RepositoryConfiguration, repoSlug: String? = nil) -> [PRMetadata] {
        if let cacheURL = config.gitHubCacheURL {
            return discoverPRs(gitHubCacheURL: cacheURL)
        }
        return discoverPRs(outputDir: config.resolvedOutputDir, repoSlug: repoSlug)
    }

    public static func discoverPR(number: Int, outputDir: String) -> PRMetadata? {
        discoverPRs(outputDir: outputDir).first(where: { $0.number == number })
    }

    /// Discover a single PR using the appropriate path from the repository configuration.
    public static func discoverPR(number: Int, config: RepositoryConfiguration) -> PRMetadata? {
        discoverPRs(config: config).first(where: { $0.number == number })
    }

    // MARK: - Load from legacy path

    public static func loadGitHubPR(outputDir: String, prNumber: Int) -> GitHubPullRequest? {
        let ghPRPath = PRRadarPhasePaths.ghPRFilePath(outputDir: outputDir, prNumber: prNumber)
        guard let data = FileManager.default.contents(atPath: ghPRPath) else { return nil }
        return try? JSONDecoder().decode(GitHubPullRequest.self, from: data)
    }

    // MARK: - Load from GitHub cache

    /// Load a PR from the shared GitHub cache directory.
    public static func loadGitHubPR(gitHubCacheURL: URL, prNumber: Int) -> GitHubPullRequest? {
        let url = gitHubCacheURL.appendingPathComponent("\(prNumber)/gh-pr.json")
        guard let data = FileManager.default.contents(atPath: url.path(percentEncoded: false)) else { return nil }
        return try? JSONDecoder().decode(GitHubPullRequest.self, from: data)
    }

    /// Load a PR using the appropriate path from the repository configuration.
    public static func loadGitHubPR(config: RepositoryConfiguration, prNumber: Int) -> GitHubPullRequest? {
        if let cacheURL = config.gitHubCacheURL {
            return loadGitHubPR(gitHubCacheURL: cacheURL, prNumber: prNumber)
        }
        return loadGitHubPR(outputDir: config.resolvedOutputDir, prNumber: prNumber)
    }

    /// Load PR comments from the shared GitHub cache directory.
    public static func loadComments(gitHubCacheURL: URL, prNumber: Int) -> GitHubPullRequestComments? {
        let url = gitHubCacheURL.appendingPathComponent("\(prNumber)/gh-comments.json")
        guard let data = FileManager.default.contents(atPath: url.path(percentEncoded: false)) else { return nil }
        return try? JSONDecoder().decode(GitHubPullRequestComments.self, from: data)
    }

    /// Load PR comments using the appropriate path from the repository configuration.
    public static func loadComments(config: RepositoryConfiguration, prNumber: Int) -> GitHubPullRequestComments? {
        if let cacheURL = config.gitHubCacheURL {
            return loadComments(gitHubCacheURL: cacheURL, prNumber: prNumber)
        }
        let metadataDir = PRRadarPhasePaths.metadataDirectory(
            outputDir: config.resolvedOutputDir, prNumber: prNumber
        )
        let path = "\(metadataDir)/\(PRRadarPhasePaths.ghCommentsFilename)"
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
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
