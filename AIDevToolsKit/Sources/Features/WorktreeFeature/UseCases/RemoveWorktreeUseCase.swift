import Foundation
import GitSDK
import UseCaseSDK

public struct RemoveWorktreeUseCase: UseCase {
    private let gitClient: GitClient
    private let listUseCase: ListWorktreesUseCase

    public init(gitClient: GitClient, listUseCase: ListWorktreesUseCase) {
        self.gitClient = gitClient
        self.listUseCase = listUseCase
    }

    @discardableResult
    public func execute(repoPath: String, worktreePath: String, force: Bool = false) async throws -> [WorktreeStatus] {
        do {
            _ = try await gitClient.removeWorktree(worktreePath: worktreePath, force: force, workingDirectory: repoPath)
        } catch {
            throw WorktreeError.removeFailed(error.localizedDescription)
        }
        return try await listUseCase.execute(repoPath: repoPath)
    }
}
