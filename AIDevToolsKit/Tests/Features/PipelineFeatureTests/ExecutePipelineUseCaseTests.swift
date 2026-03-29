import Foundation
import Testing
@testable import PipelineFeature
import PipelineSDK

// MARK: - Test doubles

private struct MockPipelineSource: PipelineSource {
    var steps: [any PipelineStep]
    var appendedSteps: [any PipelineStep] = []
    var completedStepIDs: [String] = []

    func load() async throws -> Pipeline {
        Pipeline(
            id: "mock-pipeline",
            steps: steps,
            metadata: PipelineMetadata(name: "Mock")
        )
    }

    func markStepCompleted(_ step: any PipelineStep) async throws {
        // no-op — tracking happens in the actor wrapper below
    }

    func appendSteps(_ steps: [any PipelineStep]) async throws {
        // no-op
    }
}

/// Wraps MockPipelineSource with mutation tracking.
private actor TrackingPipelineSource: PipelineSource {
    var steps: [any PipelineStep]
    private(set) var completedStepIDs: [String] = []
    private(set) var appendedSteps: [any PipelineStep] = []

    init(steps: [any PipelineStep]) {
        self.steps = steps
    }

    func load() async throws -> Pipeline {
        Pipeline(
            id: "tracking-pipeline",
            steps: steps,
            metadata: PipelineMetadata(name: "Tracking")
        )
    }

    func markStepCompleted(_ step: any PipelineStep) async throws {
        completedStepIDs.append(step.id)
    }

    func appendSteps(_ newSteps: [any PipelineStep]) async throws {
        appendedSteps.append(contentsOf: newSteps)
        steps.append(contentsOf: newSteps)
    }
}

private struct RecordingStepHandler: StepHandler {
    typealias Step = CodeChangeStep

    let actor: RecordingActor

    func execute(_ step: CodeChangeStep, context: PipelineContext) async throws -> [any PipelineStep] {
        await actor.record(step.id)
        return []
    }
}

private actor RecordingActor {
    private(set) var executedIDs: [String] = []

    func record(_ id: String) {
        executedIDs.append(id)
    }
}

/// A handler that, when it executes a step, also returns a new dynamic step.
private struct DynamicInsertionHandler: StepHandler {
    typealias Step = CodeChangeStep

    let dynamicStep: CodeChangeStep

    func execute(_ step: CodeChangeStep, context: PipelineContext) async throws -> [any PipelineStep] {
        // Only inject the dynamic step when handling the first step (id == "0")
        guard step.id == "0" else { return [] }
        return [dynamicStep]
    }
}

// MARK: - Tests

@Suite("ExecutePipelineUseCase")
struct ExecutePipelineUseCaseTests {

    private func makeStep(id: String, description: String = "", isCompleted: Bool = false) -> CodeChangeStep {
        CodeChangeStep(id: id, description: description.isEmpty ? id : description, isCompleted: isCompleted, prompt: id)
    }

    // MARK: Sequential dispatch

    @Test("Executes all pending steps in order")
    func executesStepsInOrder() async throws {
        let recorder = RecordingActor()
        let handler = RecordingStepHandler(actor: recorder)
        let steps: [any PipelineStep] = [
            makeStep(id: "0"),
            makeStep(id: "1"),
            makeStep(id: "2"),
        ]
        let source = TrackingPipelineSource(steps: steps)

        let useCase = ExecutePipelineUseCase()
        let options = ExecutePipelineUseCase.Options(
            source: source,
            context: PipelineContext(),
            handlers: [AnyStepHandler(handler)]
        )

        let result = try await useCase.run(options)

        let executedIDs = await recorder.executedIDs
        #expect(executedIDs == ["0", "1", "2"])
        #expect(result.stepsExecuted == 3)
        #expect(result.allCompleted == true)
    }

    @Test("Skips already-completed steps")
    func skipsCompletedSteps() async throws {
        let recorder = RecordingActor()
        let handler = RecordingStepHandler(actor: recorder)
        let steps: [any PipelineStep] = [
            makeStep(id: "0", isCompleted: true),
            makeStep(id: "1", isCompleted: false),
        ]
        let source = TrackingPipelineSource(steps: steps)

        let useCase = ExecutePipelineUseCase()
        let options = ExecutePipelineUseCase.Options(
            source: source,
            context: PipelineContext(),
            handlers: [AnyStepHandler(handler)]
        )

        let result = try await useCase.run(options)

        let executedIDs = await recorder.executedIDs
        #expect(executedIDs == ["1"])
        #expect(result.stepsExecuted == 1)
    }

    @Test("Skips all steps when all are already completed")
    func skipsAllWhenAllCompleted() async throws {
        let recorder = RecordingActor()
        let handler = RecordingStepHandler(actor: recorder)
        let steps: [any PipelineStep] = [
            makeStep(id: "0", isCompleted: true),
            makeStep(id: "1", isCompleted: true),
        ]
        let source = TrackingPipelineSource(steps: steps)

        let useCase = ExecutePipelineUseCase()
        let options = ExecutePipelineUseCase.Options(
            source: source,
            context: PipelineContext(),
            handlers: [AnyStepHandler(handler)]
        )

        let result = try await useCase.run(options)

        let executedIDs = await recorder.executedIDs
        #expect(executedIDs.isEmpty)
        #expect(result.stepsExecuted == 0)
    }

    // MARK: Persistence

    @Test("markStepCompleted is called after each step")
    func persistsCompletionAfterEachStep() async throws {
        let recorder = RecordingActor()
        let handler = RecordingStepHandler(actor: recorder)
        let steps: [any PipelineStep] = [
            makeStep(id: "a"),
            makeStep(id: "b"),
        ]
        let source = TrackingPipelineSource(steps: steps)

        let useCase = ExecutePipelineUseCase()
        let options = ExecutePipelineUseCase.Options(
            source: source,
            context: PipelineContext(),
            handlers: [AnyStepHandler(handler)]
        )

        _ = try await useCase.run(options)

        let completed = await source.completedStepIDs
        #expect(completed == ["a", "b"])
    }

    // MARK: Dynamic step insertion

    @Test("Dynamic steps returned by handler are appended and executed")
    func dynamicStepInsertion() async throws {
        let dynamicStep = makeStep(id: "dynamic")
        let insertionHandler = DynamicInsertionHandler(dynamicStep: dynamicStep)

        let steps: [any PipelineStep] = [makeStep(id: "0")]
        let source = TrackingPipelineSource(steps: steps)

        var progressEvents: [ExecutePipelineUseCase.Progress] = []
        let useCase = ExecutePipelineUseCase()
        let options = ExecutePipelineUseCase.Options(
            source: source,
            context: PipelineContext(),
            handlers: [AnyStepHandler(insertionHandler)]
        )

        let result = try await useCase.run(options) { event in
            progressEvents.append(event)
        }

        // The dynamic step is also executed, so total = 2
        #expect(result.stepsExecuted == 2)

        let appended = await source.appendedSteps
        #expect(appended.count == 1)
        #expect(appended.first?.id == "dynamic")

        let hasAppendedEvent = progressEvents.contains {
            if case .stepsAppended(let count) = $0 { return count == 1 }
            return false
        }
        #expect(hasAppendedEvent)
    }

    // MARK: Progress events

    @Test("Progress events are emitted in expected sequence")
    func progressEventsSequence() async throws {
        let recorder = RecordingActor()
        let handler = RecordingStepHandler(actor: recorder)
        let steps: [any PipelineStep] = [makeStep(id: "0", description: "Step Zero")]
        let source = TrackingPipelineSource(steps: steps)

        var progressEvents: [ExecutePipelineUseCase.Progress] = []
        let useCase = ExecutePipelineUseCase()
        let options = ExecutePipelineUseCase.Options(
            source: source,
            context: PipelineContext(),
            handlers: [AnyStepHandler(handler)]
        )

        _ = try await useCase.run(options) { event in
            progressEvents.append(event)
        }

        guard progressEvents.count == 3 else {
            Issue.record("Expected 3 progress events, got \(progressEvents.count)")
            return
        }

        if case .stepStarted(let desc, let index, _) = progressEvents[0] {
            #expect(desc == "Step Zero")
            #expect(index == 0)
        } else {
            Issue.record("Expected stepStarted as first event")
        }

        if case .stepCompleted(let desc, let index) = progressEvents[1] {
            #expect(desc == "Step Zero")
            #expect(index == 0)
        } else {
            Issue.record("Expected stepCompleted as second event")
        }

        if case .allCompleted(let count) = progressEvents[2] {
            #expect(count == 1)
        } else {
            Issue.record("Expected allCompleted as third event")
        }
    }

    // MARK: Error handling

    @Test("Throws noHandlerFound when no handler matches step type")
    func throwsNoHandlerFoundWhenUnhandled() async throws {
        // Source has a CodeChangeStep but we provide no handlers
        let steps: [any PipelineStep] = [makeStep(id: "0", description: "Unhandled")]
        let source = TrackingPipelineSource(steps: steps)

        let useCase = ExecutePipelineUseCase()
        let options = ExecutePipelineUseCase.Options(
            source: source,
            context: PipelineContext(),
            handlers: []
        )

        await #expect(throws: ExecutePipelineUseCase.ExecuteError.self) {
            _ = try await useCase.run(options)
        }
    }
}
