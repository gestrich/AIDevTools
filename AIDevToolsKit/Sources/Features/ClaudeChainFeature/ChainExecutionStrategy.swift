import AIOutputSDK
import ClaudeChainService
import Foundation
import GitSDK
import SweepFeature

/// Unified progress event emitted by any chain execution strategy.
public enum ChainProgressEvent: Sendable {
    case spec(RunSpecChainTaskUseCase.Progress)
    case sweep(RunSweepBatchUseCase.Progress)
}

/// Encapsulates the execution logic for a specific chain kind.
public protocol ChainExecutionStrategy: Sendable {
    var initialPhases: [ChainExecutionPhase] { get }

    func execute(
        project: ChainProject,
        repoPath: URL,
        taskIndex: Int?,
        stagingOnly: Bool,
        client: any AIClient,
        git: GitClient,
        githubAccount: String?,
        onProgress: @escaping @Sendable (ChainProgressEvent) -> Void
    ) async throws -> ExecuteSpecChainUseCase.Result
}

struct SpecChainExecutionStrategy: ChainExecutionStrategy {
    var initialPhases: [ChainExecutionPhase] { RunSpecChainTaskUseCase.phases }

    func execute(
        project: ChainProject,
        repoPath: URL,
        taskIndex: Int?,
        stagingOnly: Bool,
        client: any AIClient,
        git: GitClient,
        githubAccount: String?,
        onProgress: @escaping @Sendable (ChainProgressEvent) -> Void
    ) async throws -> ExecuteSpecChainUseCase.Result {
        let options = ExecuteSpecChainUseCase.Options(
            repoPath: repoPath,
            projectName: project.name,
            baseBranch: project.baseBranch,
            githubAccount: githubAccount,
            taskIndex: taskIndex,
            stagingOnly: stagingOnly
        )
        let useCase = ExecuteSpecChainUseCase(client: client, git: git)
        return try await useCase.run(options: options) { progress in
            onProgress(.spec(progress))
        }
    }
}

struct SweepChainExecutionStrategy: ChainExecutionStrategy {
    var initialPhases: [ChainExecutionPhase] { RunSweepBatchUseCase.phases }

    func execute(
        project: ChainProject,
        repoPath: URL,
        taskIndex: Int?,
        stagingOnly: Bool,
        client: any AIClient,
        git: GitClient,
        githubAccount: String?,
        onProgress: @escaping @Sendable (ChainProgressEvent) -> Void
    ) async throws -> ExecuteSpecChainUseCase.Result {
        let useCase = ExecuteSweepChainUseCase(client: client, git: git)
        let options = ExecuteSweepChainUseCase.Options(
            project: project,
            repoPath: repoPath,
            githubAccount: githubAccount
        )
        return try await useCase.run(options: options) { progress in
            onProgress(.sweep(progress))
        }
    }
}

public enum ChainExecutionStrategyFactory {
    public static func strategy(for kind: ChainKind) -> any ChainExecutionStrategy {
        switch kind {
        case .spec: return SpecChainExecutionStrategy()
        case .sweep: return SweepChainExecutionStrategy()
        }
    }
}
