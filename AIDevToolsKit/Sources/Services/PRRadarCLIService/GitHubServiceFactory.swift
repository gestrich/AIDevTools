import CLISDK
import CredentialService
import DataPathsService
import Foundation
import GitHubService
import GitSDK
import OctokitSDK
import PRRadarConfigService
import RepositorySDK

public struct GitHubServiceFactory: Sendable {
    public static func create(repoPath: String, githubAccount: String, explicitToken: String? = nil) async throws -> (gitHub: GitHubAPIService, gitOps: GitOperationsService) {
        let token = try await resolveToken(githubAccount: githubAccount, explicitToken: explicitToken)

        let gitOps = createGitOps(gitHubToken: token)
        let remoteURL = try await gitOps.getRemoteURL(path: repoPath)

        guard let (owner, repo) = GitHubAPIService.parseOwnerRepo(from: remoteURL) else {
            throw GitHubServiceError.cannotParseRemoteURL(remoteURL)
        }

        let octokitClient = OctokitClient(token: token)
        let gitHub = GitHubAPIService(octokitClient: octokitClient, owner: owner, repo: repo)

        return (gitHub, gitOps)
    }

    public static func createHistoryProvider(
        diffSource: DiffSource,
        gitHub: GitHubAPIService,
        gitOps: GitOperationsService,
        repoPath: String,
        prNumber: Int,
        baseBranch: String,
        headBranch: String
    ) -> GitHistoryProvider {
        switch diffSource {
        case .git:
            return LocalGitHistoryProvider(gitOps: gitOps, repoPath: repoPath, baseBranch: baseBranch, headBranch: headBranch)
        case .githubAPI:
            return GitHubAPIHistoryProvider(gitHub: gitHub, prNumber: prNumber)
        }
    }

    public static func createGitOps(gitHubToken: String? = nil) -> GitOperationsService {
        let environment: [String: String]? = gitHubToken.map { ["GH_TOKEN": $0] }
        return GitOperationsService(client: CLIClient(printOutput: false), environment: environment)
    }

    public static func createGitOps(githubAccount: String, explicitToken: String? = nil) async throws -> GitOperationsService {
        let token = try await resolveToken(githubAccount: githubAccount, explicitToken: explicitToken)
        return createGitOps(gitHubToken: token)
    }

    public static func createPRService(
        repoPath: String,
        githubAccount: String,
        explicitToken: String? = nil,
        dataPathsService: DataPathsService
    ) async throws -> GitHubPRService {
        let (gitHub, _) = try await create(repoPath: repoPath, githubAccount: githubAccount, explicitToken: explicitToken)
        let normalizedSlug = gitHub.repoSlug.replacingOccurrences(of: "/", with: "-")
        let cacheURL = try dataPathsService.path(for: .github(repoSlug: normalizedSlug))
        return GitHubPRService(rootURL: cacheURL, apiClient: gitHub)
    }

    public static func createPRService(
        repoPath: String,
        resolver: CredentialService.CredentialResolver,
        dataPathsService: DataPathsService
    ) async throws -> GitHubPRService {
        let auth = try resolver.requireGitHubAuth()
        let token: String
        switch auth {
        case .token(let pat):
            token = pat
        case .app(let appId, let installationId, let privateKeyPEM):
            token = try await GitHubAppTokenService().generateInstallationToken(
                appId: appId, installationId: installationId, privateKeyPEM: privateKeyPEM
            )
        }
        let gitOps = createGitOps(gitHubToken: token)
        let remoteURL = try await gitOps.getRemoteURL(path: repoPath)
        guard let (owner, repo) = GitHubAPIService.parseOwnerRepo(from: remoteURL) else {
            throw GitHubServiceError.cannotParseRemoteURL(remoteURL)
        }
        let octokitClient = OctokitClient(token: token)
        let gitHub = GitHubAPIService(octokitClient: octokitClient, owner: owner, repo: repo)
        let normalizedSlug = gitHub.repoSlug.replacingOccurrences(of: "/", with: "-")
        let cacheURL = try dataPathsService.path(for: .github(repoSlug: normalizedSlug))
        return GitHubPRService(rootURL: cacheURL, apiClient: gitHub)
    }

    public static func make(token: String, owner: String, repo: String) -> GitHubPRService {
        let octokitClient = OctokitClient(token: token)
        let apiService = GitHubAPIService(octokitClient: octokitClient, owner: owner, repo: repo)
        let normalizedSlug = "\(owner)-\(repo)"
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            preconditionFailure("Application Support directory unavailable")
        }
        let cacheURL = appSupportURL.appendingPathComponent("AIDevToolsKit/github/\(normalizedSlug)")
        return GitHubPRService(rootURL: cacheURL, apiClient: apiService)
    }

    public static func resolveToken(githubAccount: String, explicitToken: String? = nil) async throws -> String {
        if let explicitToken { return explicitToken }
        let resolver = CredentialResolver.createPlatform(githubAccount: githubAccount)
        guard let auth = resolver.getGitHubAuth() else {
            throw GitHubServiceError.missingToken
        }
        switch auth {
        case .token(let pat):
            return pat
        case .app(let appId, let installationId, let privateKeyPEM):
            return try await GitHubAppTokenService().generateInstallationToken(
                appId: appId, installationId: installationId, privateKeyPEM: privateKeyPEM
            )
        }
    }
}
