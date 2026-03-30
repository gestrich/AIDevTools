import Foundation
import PipelineSDK
import UseCaseSDK

public struct ExecutePipelineUseCase: UseCase {

    public init() {}

    public func run(
        _ options: ExecutePipelineOptions,
        onProgress: (@Sendable (ExecutePipelineProgress) -> Void)? = nil
    ) async throws -> ExecutePipelineResult {
        let pipeline = try await options.source.load()

        // Seed the local mutable array — the execution loop appends dynamic steps here
        var localSteps: [any PipelineStep] = pipeline.steps
        let currentContext = options.context
        var stepsExecuted = 0
        var index = 0

        while index < localSteps.count {
            let step = localSteps[index]

            guard !step.isCompleted else {
                index += 1
                continue
            }

            onProgress?(.stepStarted(
                stepDescription: step.description,
                index: index,
                total: localSteps.count
            ))

            // Dispatch to the first handler that accepts this step type
            var newSteps: [any PipelineStep] = []
            var handled = false
            for handler in options.handlers {
                if let result = try await handler.tryExecute(step, context: currentContext) {
                    newSteps = result
                    handled = true
                    break
                }
            }

            guard handled else {
                throw ExecutePipelineError.noHandlerFound(stepDescription: step.description)
            }

            // Persist completion before moving on
            try await options.source.markStepCompleted(step)
            stepsExecuted += 1
            onProgress?(.stepCompleted(stepDescription: step.description, index: index))

            // Append dynamic steps emitted by the handler
            if !newSteps.isEmpty {
                localSteps.append(contentsOf: newSteps)
                try await options.source.appendSteps(newSteps)
                onProgress?(.stepsAppended(count: newSteps.count))
            }

            index += 1
        }

        onProgress?(.allCompleted(stepsExecuted: stepsExecuted))
        return ExecutePipelineResult(stepsExecuted: stepsExecuted, allCompleted: true)
    }
}
