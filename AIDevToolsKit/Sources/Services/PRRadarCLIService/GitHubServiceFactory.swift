import CLISDK
import DataPathsService
import Foundation
import GitHubService
import GitSDK
import OctokitSDK
import PRRadarConfigService

public struct GitHubServiceFactory: Sendable {
    public static func create(repoPath: String, githubAccount: String) async throws -> (gitHub: GitHubAPIService, gitOps: GitOperationsService) {
        let token = try await resolveToken(githubAccount: githubAccount)

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

    public static func createGitOps(githubAccount: String) async throws -> GitOperationsService {
        let token = try await resolveToken(githubAccount: githubAccount)
        return createGitOps(gitHubToken: token)
    }

    public static func createPRService(
        repoPath: String,
        githubAccount: String,
        dataPathsService: DataPathsService
    ) async throws -> GitHubPRService {
        let (gitHub, _) = try await create(repoPath: repoPath, githubAccount: githubAccount)
        let normalizedSlug = gitHub.repoSlug.replacingOccurrences(of: "/", with: "-")
        let cacheURL = try dataPathsService.path(for: .github(repoSlug: normalizedSlug))
        return GitHubPRService(rootURL: cacheURL, apiClient: gitHub)
    }

    public static func resolveToken(githubAccount: String) async throws -> String {
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
