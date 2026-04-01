import EvalService
import Foundation
import MarkdownPlannerService
import RepositorySDK
import UseCaseSDK

public struct RemoveRepositoryWithSettingsUseCase: UseCase {
    private let evalSettingsStore: EvalRepoSettingsStore
    private let planSettingsStore: MarkdownPlannerRepoSettingsStore
    private let removeRepository: RemoveRepositoryUseCase

    public init(
        evalSettingsStore: EvalRepoSettingsStore,
        planSettingsStore: MarkdownPlannerRepoSettingsStore,
        removeRepository: RemoveRepositoryUseCase
    ) {
        self.evalSettingsStore = evalSettingsStore
        self.planSettingsStore = planSettingsStore
        self.removeRepository = removeRepository
    }

    public func run(id: UUID) throws {
        try removeRepository.run(id: id)
    }
}
