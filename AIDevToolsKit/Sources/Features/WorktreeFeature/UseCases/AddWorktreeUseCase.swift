import Foundation
import GitSDK
import UseCaseSDK

public struct AddWorktreeUseCase: UseCase {
    private let gitClient: GitClient
    private let listUseCase: ListWorktreesUseCase

    public init(gitClient: GitClient, listUseCase: ListWorktreesUseCase) {
        self.gitClient = gitClient
        self.listUseCase = listUseCase
    }

    @discardableResult
    public func execute(repoPath: String, destination: String, branch: String) async throws -> [WorktreeStatus] {
        do {
            _ = try await gitClient.createWorktree(baseBranch: branch, destination: destination, workingDirectory: repoPath)
        } catch {
            throw WorktreeError.addFailed(error.localizedDescription)
        }
        return try await listUseCase.execute(repoPath: repoPath)
    }
}
