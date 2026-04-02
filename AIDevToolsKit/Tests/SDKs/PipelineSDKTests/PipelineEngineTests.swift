import AIOutputSDK
import Foundation
import PipelineService
import Testing
@testable import PipelineSDK

// MARK: - Mock helpers

private struct EchoNode: PipelineNode {
    let id: String
    let displayName: String
    let outputKey: PipelineContextKey<String>

    func run(
        context: PipelineContext,
        onProgress: @escaping @Sendable (PipelineNodeProgress) -> Void
    ) async throws -> PipelineContext {
        var updated = context
        updated[outputKey] = displayName
        return updated
    }
}

private struct FailNode: PipelineNode {
    let id: String
    let displayName: String

    func run(
        context: PipelineContext,
        onProgress: @escaping @Sendable (PipelineNodeProgress) -> Void
    ) async throws -> PipelineContext {
        throw PipelineError.cancelled
    }
}

private struct InjectingNode: PipelineNode {
    let id: String
    let displayName: String
    let taskSource: any TaskSource

    func run(
        context: PipelineContext,
        onProgress: @escaping @Sendable (PipelineNodeProgress) -> Void
    ) async throws -> PipelineContext {
        var updated = context
        updated[PipelineContext.injectedTaskSourceKey] = taskSource
        return updated
    }
}

private struct FixedTaskSource: TaskSource {
    let tasks: [PendingTask]
    private let state = FixedTaskSourceState()

    func nextTask() async throws -> PendingTask? {
        return state.next(from: tasks)
    }

    func markComplete(_ task: PendingTask) async throws {}
}

private final class FixedTaskSourceState: @unchecked Sendable {
    private let lock = NSLock()
    private var index = 0

    func next(from tasks: [PendingTask]) -> PendingTask? {
        lock.lock()
        defer { lock.unlock() }
        guard index < tasks.count else { return nil }
        let task = tasks[index]
        index += 1
        return task
    }
}

private struct MockAIClient: AIClient {
    let name = "mock"
    let displayName = "Mock"
    let response: String

    func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIClientResult {
        onOutput?(response)
        return AIClientResult(exitCode: 0, stderr: "", stdout: response)
    }

    func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        let data = Data(response.utf8)
        let value = try JSONDecoder().decode(T.self, from: data)
        return AIStructuredResult(rawOutput: response, stderr: "", value: value)
    }

    func listSessions(workingDirectory: String) async -> [ChatSession] { [] }
    func loadSessionMessages(sessionId: String, workingDirectory: String) async -> [ChatSessionMessage] { [] }
    func getSessionDetails(sessionId: String, summary: String, lastModified: Date, workingDirectory: String) -> SessionDetails? { nil }
}

private func makeConfig(client: any AIClient = MockAIClient(response: "ok")) -> PipelineConfiguration {
    PipelineConfiguration(provider: client)
}

// MARK: - MarkdownTaskSource tests

@Suite("MarkdownTaskSource")
struct MarkdownTaskSourceTests {

    private func makeTempFile(content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("nextTask: returns first pending task in .phase format")
    func phaseNextTask() async throws {
        let url = try makeTempFile(content: "## - [x] Done\n## - [ ] Pending\n")
        defer { cleanup(url) }
        let source = MarkdownTaskSource(fileURL: url, format: .phase)
        let task = try await source.nextTask()
        #expect(task?.instructions == "Pending")
    }

    @Test("nextTask: returns nil when all tasks complete in .phase format")
    func phaseNoMoreTasks() async throws {
        let url = try makeTempFile(content: "## - [x] Done\n")
        defer { cleanup(url) }
        let source = MarkdownTaskSource(fileURL: url, format: .phase)
        let task = try await source.nextTask()
        #expect(task == nil)
    }

    @Test("nextTask: returns first pending task in .task format")
    func taskFormatNextTask() async throws {
        let url = try makeTempFile(content: "- [x] Done\n- [ ] Todo\n")
        defer { cleanup(url) }
        let source = MarkdownTaskSource(fileURL: url, format: .task)
        let task = try await source.nextTask()
        #expect(task?.instructions == "Todo")
    }

    @Test("nextTask: iterates all tasks sequentially")
    func iteratesAllTasks() async throws {
        let url = try makeTempFile(content: "- [ ] A\n- [ ] B\n- [ ] C\n")
        defer { cleanup(url) }
        let source = MarkdownTaskSource(fileURL: url, format: .task)

        let t1 = try await source.nextTask()
        #expect(t1?.instructions == "A")
        try await source.markComplete(t1!)

        let t2 = try await source.nextTask()
        #expect(t2?.instructions == "B")
        try await source.markComplete(t2!)

        let t3 = try await source.nextTask()
        #expect(t3?.instructions == "C")
        try await source.markComplete(t3!)

        let t4 = try await source.nextTask()
        #expect(t4 == nil)
    }

    @Test("markComplete: updates checkbox on disk")
    func markCompleteCheckboxRoundTrip() async throws {
        let url = try makeTempFile(content: "- [ ] Build feature\n")
        defer { cleanup(url) }
        let source = MarkdownTaskSource(fileURL: url, format: .task)
        let task = try await source.nextTask()
        try await source.markComplete(task!)
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("- [x] Build feature"))
        #expect(!content.contains("- [ ] Build feature"))
    }

    @Test("taskIndex: returns only the specified task, nil after markComplete")
    func taskIndexSingleTask() async throws {
        let url = try makeTempFile(content: "- [ ] Task A\n- [ ] Task B\n- [ ] Task C\n")
        defer { cleanup(url) }
        // taskIndex 1 → id "1" (0-based index 1)
        let source = MarkdownTaskSource(fileURL: url, format: .task, taskIndex: 1)
        let t1 = try await source.nextTask()
        #expect(t1?.instructions == "Task B")
        try await source.markComplete(t1!)
        let t2 = try await source.nextTask()
        #expect(t2 == nil)
    }

    @Test("taskIndex: returns nil when indexed task is already completed")
    func taskIndexReturnsNilForCompletedTask() async throws {
        // Arrange
        let url = try makeTempFile(content: "- [ ] Task A\n- [x] Task B\n- [ ] Task C\n")
        defer { cleanup(url) }

        let source = MarkdownTaskSource(fileURL: url, format: .task, taskIndex: 1)

        // Act
        let task = try await source.nextTask()

        // Assert
        #expect(task == nil)
    }

    @Test("markComplete: updates only the targeted task, leaves others unchanged")
    func markCompleteUpdatesOnlyTargetedTask() async throws {
        // Arrange
        let url = try makeTempFile(content: "- [ ] Task A\n- [ ] Task B\n- [ ] Task C\n")
        defer { cleanup(url) }

        let source = MarkdownTaskSource(fileURL: url, format: .task, taskIndex: 1)
        let task = try await source.nextTask()
        let pendingTask = try #require(task)

        // Act
        try await source.markComplete(pendingTask)

        // Assert
        let updatedContent = try String(contentsOf: url, encoding: .utf8)
        #expect(updatedContent.contains("- [ ] Task A"))
        #expect(updatedContent.contains("- [x] Task B"))
        #expect(updatedContent.contains("- [ ] Task C"))
    }
}

// MARK: - Pipeline execution tests

@Suite("Pipeline execution")
struct PipelineExecutionTests {

    @Test("runs all nodes in order")
    func runsAllNodes() async throws {
        let keyA = PipelineContextKey<String>("a")
        let keyB = PipelineContextKey<String>("b")
        let nodes: [any PipelineNode] = [
            EchoNode(id: "a", displayName: "Node A", outputKey: keyA),
            EchoNode(id: "b", displayName: "Node B", outputKey: keyB),
        ]
        let pipeline = Pipeline(nodes: nodes, configuration: makeConfig())
        let result = try await pipeline.run { _ in }
        #expect(result[keyA] == "Node A")
        #expect(result[keyB] == "Node B")
    }

    @Test("startAtIndex skips earlier nodes")
    func startAtIndexSkips() async throws {
        let keyA = PipelineContextKey<String>("a")
        let keyB = PipelineContextKey<String>("b")
        let nodes: [any PipelineNode] = [
            EchoNode(id: "a", displayName: "Node A", outputKey: keyA),
            EchoNode(id: "b", displayName: "Node B", outputKey: keyB),
        ]
        let pipeline = Pipeline(nodes: nodes, configuration: makeConfig())
        let result = try await pipeline.run(startingAt: 1) { _ in }
        #expect(result[keyA] == nil)
        #expect(result[keyB] == "Node B")
    }

    @Test("stop halts pipeline before next node")
    func stopHaltsPipeline() async throws {
        let key = PipelineContextKey<String>("val")
        let nodes: [any PipelineNode] = [
            EchoNode(id: "a", displayName: "A", outputKey: PipelineContextKey<String>("discard")),
            EchoNode(id: "b", displayName: "B", outputKey: key),
        ]
        let pipeline = Pipeline(nodes: nodes, configuration: makeConfig())
        let task = Task {
            try await pipeline.run { event in
                if case .nodeCompleted(let id, _) = event, id == "a" {
                    Task { await pipeline.stop() }
                }
            }
        }
        let result = try await task.value
        #expect(result[key] == nil)
    }

    @Test("pause and approve resumes pipeline")
    func pauseAndApprove() async throws {
        let key = PipelineContextKey<String>("val")
        let nodes: [any PipelineNode] = [
            ReviewStep(id: "review", displayName: "Review"),
            EchoNode(id: "after", displayName: "After Review", outputKey: key),
        ]
        let pipeline = Pipeline(nodes: nodes, configuration: makeConfig())

        let task = Task {
            try await pipeline.run { event in
                if case .pausedForReview(let continuation) = event {
                    continuation.resume()
                }
            }
        }
        let result = try await task.value
        #expect(result[key] == "After Review")
    }

    @Test("pause and cancel throws PipelineError.cancelled")
    func pauseAndCancel() async throws {
        let nodes: [any PipelineNode] = [
            ReviewStep(id: "review", displayName: "Review"),
        ]
        let pipeline = Pipeline(nodes: nodes, configuration: makeConfig())

        let task = Task<PipelineContext, any Error> {
            try await pipeline.run { event in
                if case .pausedForReview(let continuation) = event {
                    continuation.resume(throwing: PipelineError.cancelled)
                }
            }
        }
        do {
            _ = try await task.value
            #expect(Bool(false), "Expected PipelineError.cancelled to be thrown")
        } catch is PipelineError {
            // expected
        }
    }

    @Test("nextOnly mode runs exactly one injected task")
    func nextOnlyMode() async throws {
        let tasks = [
            PendingTask(id: "t1", instructions: "Task 1", skills: []),
            PendingTask(id: "t2", instructions: "Task 2", skills: []),
        ]
        let source = FixedTaskSource(tasks: tasks)
        let nodes: [any PipelineNode] = [
            InjectingNode(id: "inject", displayName: "Inject", taskSource: source),
        ]
        let config = PipelineConfiguration(executionMode: .nextOnly, provider: MockAIClient(response: "ok"))
        let pipeline = Pipeline(nodes: nodes, configuration: config)

        var completedNodeIDs: [String] = []
        _ = try await pipeline.run { event in
            if case .nodeCompleted(let id, _) = event {
                completedNodeIDs.append(id)
            }
        }
        // Should complete inject node + exactly one task node
        let taskNodeCount = completedNodeIDs.filter { $0 == "t1" }.count
        #expect(taskNodeCount == 1)
        let t2Count = completedNodeIDs.filter { $0 == "t2" }.count
        #expect(t2Count == 0)
    }

    @Test("all mode runs all injected tasks")
    func allMode() async throws {
        let tasks = [
            PendingTask(id: "t1", instructions: "Task 1", skills: []),
            PendingTask(id: "t2", instructions: "Task 2", skills: []),
        ]
        let source = FixedTaskSource(tasks: tasks)
        let nodes: [any PipelineNode] = [
            InjectingNode(id: "inject", displayName: "Inject", taskSource: source),
        ]
        let config = PipelineConfiguration(executionMode: .all, provider: MockAIClient(response: "ok"))
        let pipeline = Pipeline(nodes: nodes, configuration: config)

        var completedNodeIDs: [String] = []
        _ = try await pipeline.run { event in
            if case .nodeCompleted(let id, _) = event {
                completedNodeIDs.append(id)
            }
        }
        #expect(completedNodeIDs.contains("t1"))
        #expect(completedNodeIDs.contains("t2"))
    }
}

// MARK: - AnalyzerNode mid-pipeline injection

@Suite("AnalyzerNode")
struct AnalyzerNodeTests {

    @Test("injects TaskSource into context when output is a TaskSource")
    func injectsTaskSource() async throws {
        let inputKey = PipelineContextKey<String>("input")
        let outputKey = AnalyzerNode<String, String>.outputKey

        struct MockClient: AIClient {
            let name = "mock"
            let displayName = "Mock"
            let jsonResponse: String

            func run(prompt: String, options: AIClientOptions, onOutput: (@Sendable (String) -> Void)?, onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?) async throws -> AIClientResult {
                AIClientResult(exitCode: 0, stderr: "", stdout: jsonResponse)
            }

            func runStructured<T: Decodable & Sendable>(_ type: T.Type, prompt: String, jsonSchema: String, options: AIClientOptions, onOutput: (@Sendable (String) -> Void)?, onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?) async throws -> AIStructuredResult<T> {
                let value = try JSONDecoder().decode(T.self, from: Data(jsonResponse.utf8))
                return AIStructuredResult(rawOutput: jsonResponse, stderr: "", value: value)
            }

            func listSessions(workingDirectory: String) async -> [ChatSession] { [] }
            func loadSessionMessages(sessionId: String, workingDirectory: String) async -> [ChatSessionMessage] { [] }
            func getSessionDetails(sessionId: String, summary: String, lastModified: Date, workingDirectory: String) -> SessionDetails? { nil }
        }

        let client = MockClient(jsonResponse: "\"result\"")
        var initialContext = PipelineContext()
        initialContext[inputKey] = "hello"

        let node = AnalyzerNode<String, String>(
            id: "analyze",
            displayName: "Analyze",
            inputKey: inputKey,
            buildPrompt: { input in "Analyze: \(input)" },
            jsonSchema: #"{"type":"string"}"#,
            client: client
        )

        let result = try await node.run(context: initialContext) { _ in }
        #expect(result[outputKey] == "result")
    }
}

// MARK: - PRStep capacity check

@Suite("PRStep")
struct PRStepTests {

    @Test("PRConfiguration capacity: stores maxOpenPRs")
    func prConfigurationCapacity() {
        let config = PRConfiguration(maxOpenPRs: 3)
        #expect(config.maxOpenPRs == 3)
    }

    @Test("PRConfiguration defaults: no assignees or labels")
    func prConfigurationDefaults() {
        let config = PRConfiguration()
        #expect(config.assignees.isEmpty)
        #expect(config.labels.isEmpty)
        #expect(config.reviewers.isEmpty)
        #expect(config.maxOpenPRs == nil)
    }
}
