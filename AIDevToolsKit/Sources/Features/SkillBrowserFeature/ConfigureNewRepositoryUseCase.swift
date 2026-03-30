import EvalService
import Foundation
import MarkdownPlannerService
import RepositorySDK
import UseCaseSDK

public struct ConfigureNewRepositoryUseCase: UseCase {
    private let addRepository: AddRepositoryUseCase
    private let updateRepository: UpdateRepositoryUseCase
    private let evalSettingsStore: EvalRepoSettingsStore
    private let planSettingsStore: MarkdownPlannerRepoSettingsStore

    public init(
        addRepository: AddRepositoryUseCase,
        evalSettingsStore: EvalRepoSettingsStore,
        planSettingsStore: MarkdownPlannerRepoSettingsStore,
        updateRepository: UpdateRepositoryUseCase
    ) {
        self.addRepository = addRepository
        self.evalSettingsStore = evalSettingsStore
        self.planSettingsStore = planSettingsStore
        self.updateRepository = updateRepository
    }

    public func run(
        repository: RepositoryInfo,
        casesDirectory: String? = nil,
        completedDirectory: String? = nil,
        proposedDirectory: String? = nil
    ) throws -> RepositoryInfo {
        let added = try addRepository.run(path: repository.path, name: repository.name)
        try updateRepository.run(repository.with(id: added.id))
        if let casesDirectory {
            try evalSettingsStore.update(repoId: added.id, casesDirectory: casesDirectory)
        }
        if completedDirectory != nil || proposedDirectory != nil {
            try planSettingsStore.update(
                repoId: added.id,
                proposedDirectory: proposedDirectory,
                completedDirectory: completedDirectory
            )
        }
        return added
    }
}
