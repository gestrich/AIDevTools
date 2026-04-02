import Foundation

public struct PipelineRunner: Sendable {

    public init() {}

    public func run(
        nodes: [any PipelineNode],
        configuration: PipelineConfiguration,
        startingAt startIndex: Int = 0,
        initialContext: PipelineContext = PipelineContext(),
        onProgress: @escaping @Sendable (PipelineEvent) -> Void
    ) async throws -> PipelineContext {
        var context = initialContext
        let startTime = Date()

        for (index, node) in nodes.enumerated() {
            guard index >= startIndex else { continue }
            guard !Task.isCancelled else { break }

            if let maxMinutes = configuration.maxMinutes {
                let elapsed = Date().timeIntervalSince(startTime) / 60
                if elapsed >= Double(maxMinutes) { break }
            }

            onProgress(.nodeStarted(id: node.id, displayName: node.displayName))

            if node is ReviewStep {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    onProgress(.pausedForReview(continuation: continuation))
                }
            } else {
                let nodeID = node.id
                context = try await node.run(context: context) { progress in
                    onProgress(.nodeProgress(id: nodeID, progress: progress))
                }
            }

            onProgress(.nodeCompleted(id: node.id, displayName: node.displayName))

            if let injectedSource = context[PipelineContext.injectedTaskSourceKey] {
                context[PipelineContext.injectedTaskSourceKey] = nil
                context = try await drainTaskSource(injectedSource, configuration: configuration, context: context, onProgress: onProgress)
            }
        }

        onProgress(.completed(context: context))
        return context
    }

    // MARK: - Private

    private func drainTaskSource(
        _ source: any TaskSource,
        configuration: PipelineConfiguration,
        context: PipelineContext,
        onProgress: @escaping @Sendable (PipelineEvent) -> Void
    ) async throws -> PipelineContext {
        var context = context
        var nextTask = try await source.nextTask()
        while let task = nextTask {
            guard !Task.isCancelled else { break }

            let taskNode = AITask<String>(
                id: task.id,
                displayName: String(task.instructions.prefix(60)),
                instructions: task.instructions,
                client: configuration.provider,
                workingDirectory: configuration.workingDirectory,
                environment: configuration.environment
            )

            onProgress(.nodeStarted(id: taskNode.id, displayName: taskNode.displayName))
            let taskNodeID = taskNode.id
            context = try await taskNode.run(context: context) { progress in
                onProgress(.nodeProgress(id: taskNodeID, progress: progress))
            }
            onProgress(.nodeCompleted(id: taskNode.id, displayName: taskNode.displayName))

            try await source.markComplete(task)

            if configuration.executionMode == .nextOnly { break }

            nextTask = try await source.nextTask()
            if nextTask != nil {
                try await configuration.betweenTasks?()
            }
        }
        return context
    }
}
