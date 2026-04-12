import DataPathsService
import EnvironmentSDK
import Foundation
import PRRadarModelsService
import RepositorySDK

public struct PRRadarRepoConfig: Sendable {
    public let id: UUID
    public let name: String
    public let repoPath: String
    public let outputDir: String
    public let rulePaths: [RulePath]
    public let agentScriptPath: String
    public let githubAccount: String?
    public let diffSource: DiffSource
    public let defaultBaseBranch: String
    public let dataRootURL: URL?
    public let explicitToken: String?

    public init(
        id: UUID = UUID(),
        name: String,
        repoPath: String,
        outputDir: String,
        rulePaths: [RulePath] = [],
        agentScriptPath: String,
        githubAccount: String?,
        diffSource: DiffSource = .git,
        defaultBaseBranch: String,
        dataRootURL: URL? = nil,
        explicitToken: String? = nil
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.outputDir = outputDir
        self.rulePaths = rulePaths
        self.agentScriptPath = agentScriptPath
        self.githubAccount = githubAccount
        self.diffSource = diffSource
        self.defaultBaseBranch = defaultBaseBranch
        self.dataRootURL = dataRootURL
        self.explicitToken = explicitToken
    }

    public static func make(
        from info: RepositoryConfiguration,
        settings: PRRadarRepoSettings,
        outputDir: String,
        agentScriptPath: String,
        dataRootURL: URL? = nil,
        explicitToken: String? = nil
    ) -> PRRadarRepoConfig {
        PRRadarRepoConfig(
            id: info.id,
            name: info.name,
            repoPath: info.path.path(percentEncoded: false),
            outputDir: outputDir,
            rulePaths: settings.rulePaths,
            agentScriptPath: agentScriptPath,
            githubAccount: info.credentialAccount,
            diffSource: settings.diffSource,
            defaultBaseBranch: info.pullRequest?.baseBranch ?? "main",
            dataRootURL: dataRootURL,
            explicitToken: explicitToken
        )
    }

    public static var defaultRulePaths: [RulePath] {
        [RulePath(name: "default", path: "code-review-rules", isDefault: true)]
    }

    public var defaultRulePath: RulePath? {
        rulePaths.first(where: { $0.isDefault }) ?? rulePaths.first
    }

    public var resolvedDefaultRulesDir: String {
        guard let defaultPath = defaultRulePath else { return "" }
        return resolvedRulesDir(for: defaultPath)
    }

    public var allResolvedRulesDirs: [String] {
        rulePaths.map { resolvedRulesDir(for: $0) }
    }

    public func resolvedRulesDir(for rulePath: RulePath) -> String {
        PathUtilities.resolve(rulePath.path, relativeTo: repoPath)
    }

    public func resolvedRulesDir(named name: String) -> String? {
        guard let rulePath = rulePaths.first(where: { $0.name == name }) else {
            return nil
        }
        return resolvedRulesDir(for: rulePath)
    }

    public var resolvedOutputDir: String {
        PathUtilities.resolve(outputDir, relativeTo: repoPath)
    }

    public func prDataDirectory(for prNumber: Int) -> String {
        "\(resolvedOutputDir)/\(prNumber)"
    }

    /// URL for the shared GitHub PR cache for this repo, if a data root is available.
    ///
    /// Computed from `dataRootURL` and the `owner-repo` slug derived from the local git config.
    public var gitHubCacheURL: URL? {
        guard let dataRootURL,
              let slug = PRDiscoveryService.repoSlug(fromRepoPath: repoPath) else { return nil }
        let normalizedSlug = slug.replacingOccurrences(of: "/", with: "-")
        return dataRootURL.appendingPathComponent(ServicePath.github(repoSlug: normalizedSlug).relativePath)
    }

    /// Returns the shared GitHub PR cache URL, or throws if `dataRootURL` is not configured.
    public func requireGitHubCacheURL() throws -> URL {
        guard let url = gitHubCacheURL else {
            throw PRRadarRepoConfigError.noDataRoot
        }
        return url
    }

    public func makeFilter(
        dateFilter: PRDateFilter? = nil,
        state: PRState? = nil,
        baseBranch: String? = nil,
        authorLogin: String? = nil
    ) -> PRFilter {
        let resolvedBase: String?
        if let baseBranch {
            resolvedBase = (baseBranch.lowercased() == "all" || baseBranch.isEmpty) ? nil : baseBranch
        } else {
            resolvedBase = defaultBaseBranch
        }
        return PRFilter(
            authorLogin: authorLogin,
            baseBranch: resolvedBase,
            dateFilter: dateFilter,
            state: state ?? .open
        )
    }
}
