import Foundation
import Testing
@testable import PipelineSDK

@Suite("MarkdownPipelineSource")
struct MarkdownPipelineSourceTests {

    // MARK: - Helpers

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

    // MARK: - Phase format parsing

    @Test("Phase format: parses pending step")
    func phaseFormatParsePending() async throws {
        let url = try makeTempFile(content: "## - [ ] Do the thing\n")
        defer { cleanup(url) }

        let source = MarkdownPipelineSource(fileURL: url, format: .phase)
        let pipeline = try await source.load()

        #expect(pipeline.steps.count == 1)
        let step = try #require(pipeline.steps.first as? CodeChangeStep)
        #expect(step.description == "Do the thing")
        #expect(step.isCompleted == false)
    }

    @Test("Phase format: parses completed step")
    func phaseFormatParseCompleted() async throws {
        let url = try makeTempFile(content: "## - [x] Done step\n")
        defer { cleanup(url) }

        let source = MarkdownPipelineSource(fileURL: url, format: .phase)
        let pipeline = try await source.load()

        #expect(pipeline.steps.count == 1)
        let step = try #require(pipeline.steps.first as? CodeChangeStep)
        #expect(step.description == "Done step")
        #expect(step.isCompleted == true)
    }

    @Test("Phase format: parses mixed completed and pending")
    func phaseFormatParseMixed() async throws {
        let content = """
        ## - [x] Phase 1
        ## - [ ] Phase 2
        ## - [x] Phase 3
        ## - [ ] Phase 4
        """
        let url = try makeTempFile(content: content)
        defer { cleanup(url) }

        let source = MarkdownPipelineSource(fileURL: url, format: .phase)
        let pipeline = try await source.load()

        #expect(pipeline.steps.count == 4)
        let steps = pipeline.steps.compactMap { $0 as? CodeChangeStep }
        #expect(steps[0].isCompleted == true)
        #expect(steps[1].isCompleted == false)
        #expect(steps[2].isCompleted == true)
        #expect(steps[3].isCompleted == false)
    }

    @Test("Phase format: empty file produces no steps")
    func phaseFormatEmptyFile() async throws {
        let url = try makeTempFile(content: "")
        defer { cleanup(url) }

        let source = MarkdownPipelineSource(fileURL: url, format: .phase)
        let pipeline = try await source.load()

        #expect(pipeline.steps.isEmpty)
    }

    @Test("Phase format: all complete produces all completed steps")
    func phaseFormatAllComplete() async throws {
        let content = "## - [x] Step A\n## - [x] Step B\n"
        let url = try makeTempFile(content: content)
        defer { cleanup(url) }

        let source = MarkdownPipelineSource(fileURL: url, format: .phase)
        let pipeline = try await source.load()

        #expect(pipeline.steps.count == 2)
        #expect(pipeline.steps.allSatisfy { $0.isCompleted })
    }

    // MARK: - Task format parsing

    @Test("Task format: parses pending step")
    func taskFormatParsePending() async throws {
        let url = try makeTempFile(content: "- [ ] Implement feature\n")
        defer { cleanup(url) }

        let source = MarkdownPipelineSource(fileURL: url, format: .task, appendCreatePRStep: false)
        let pipeline = try await source.load()

        #expect(pipeline.steps.count == 1)
        let step = try #require(pipeline.steps.first as? CodeChangeStep)
        #expect(step.description == "Implement feature")
        #expect(step.isCompleted == false)
    }

    @Test("Task format: parses completed step with lowercase x")
    func taskFormatParseCompletedLowercase() async throws {
        let url = try makeTempFile(content: "- [x] Done task\n")
        defer { cleanup(url) }

        let source = MarkdownPipelineSource(fileURL: url, format: .task, appendCreatePRStep: false)
        let pipeline = try await source.load()

        #expect(pipeline.steps.count == 1)
        let step = try #require(pipeline.steps.first as? CodeChangeStep)
        #expect(step.isCompleted == true)
    }

    @Test("Task format: parses completed step with uppercase X")
    func taskFormatParseCompletedUppercase() async throws {
        let url = try makeTempFile(content: "- [X] Done task\n")
        defer { cleanup(url) }

        let source = MarkdownPipelineSource(fileURL: url, format: .task, appendCreatePRStep: false)
        let pipeline = try await source.load()

        #expect(pipeline.steps.count == 1)
        let step = try #require(pipeline.steps.first as? CodeChangeStep)
        #expect(step.isCompleted == true)
    }

    @Test("Task format: parses mixed completed and pending")
    func taskFormatParseMixed() async throws {
        let content = """
        - [x] Task 1
        - [ ] Task 2
        - [x] Task 3
        """
        let url = try makeTempFile(content: content)
        defer { cleanup(url) }

        let source = MarkdownPipelineSource(fileURL: url, format: .task, appendCreatePRStep: false)
        let pipeline = try await source.load()

        #expect(pipeline.steps.count == 3)
        let steps = pipeline.steps.compactMap { $0 as? CodeChangeStep }
        #expect(steps[0].isCompleted == true)
        #expect(steps[1].isCompleted == false)
        #expect(steps[2].isCompleted == true)
    }

    @Test("Task format: default appendCreatePRStep is true")
    func taskFormatDefaultAppendCreatePRStep() async throws {
        let url = try makeTempFile(content: "- [ ] Task A\n")
        defer { cleanup(url) }

        let source = MarkdownPipelineSource(fileURL: url, format: .task)
        let pipeline = try await source.load()

        // 1 CodeChangeStep + 1 CreatePRStep
        #expect(pipeline.steps.count == 2)
        #expect(pipeline.steps.last is CreatePRStep)
    }

    @Test("Phase format: default appendCreatePRStep is false")
    func phaseFormatDefaultNoCreatePRStep() async throws {
        let url = try makeTempFile(content: "## - [ ] Phase 1\n")
        defer { cleanup(url) }

        let source = MarkdownPipelineSource(fileURL: url, format: .phase)
        let pipeline = try await source.load()

        #expect(pipeline.steps.count == 1)
        #expect(pipeline.steps.first is CodeChangeStep)
    }

    // MARK: - markStepCompleted

    @Test("Phase format: markStepCompleted updates checkbox on disk")
    func phaseFormatMarkStepCompleted() async throws {
        let url = try makeTempFile(content: "## - [ ] Implement validation\n")
        defer { cleanup(url) }

        let source = MarkdownPipelineSource(fileURL: url, format: .phase)
        let pipeline = try await source.load()
        let step = try #require(pipeline.steps.first as? CodeChangeStep)

        try await source.markStepCompleted(step)

        let updatedContent = try String(contentsOf: url, encoding: .utf8)
        #expect(updatedContent.contains("## - [x] Implement validation"))
        #expect(!updatedContent.contains("## - [ ] Implement validation"))
    }

    @Test("Task format: markStepCompleted updates checkbox on disk")
    func taskFormatMarkStepCompleted() async throws {
        let url = try makeTempFile(content: "- [ ] Build feature\n")
        defer { cleanup(url) }

        let source = MarkdownPipelineSource(fileURL: url, format: .task, appendCreatePRStep: false)
        let pipeline = try await source.load()
        let step = try #require(pipeline.steps.first as? CodeChangeStep)

        try await source.markStepCompleted(step)

        let updatedContent = try String(contentsOf: url, encoding: .utf8)
        #expect(updatedContent.contains("- [x] Build feature"))
        #expect(!updatedContent.contains("- [ ] Build feature"))
    }

    @Test("markStepCompleted: silently skips CreatePRStep")
    func markStepCompletedSkipsCreatePRStep() async throws {
        let content = "- [ ] Task\n"
        let url = try makeTempFile(content: content)
        defer { cleanup(url) }

        let source = MarkdownPipelineSource(fileURL: url, format: .task, appendCreatePRStep: false)
        let prStep = CreatePRStep(id: "pr", description: "Create PR", titleTemplate: "title", bodyTemplate: "body")

        // Should not throw
        try await source.markStepCompleted(prStep)

        let updatedContent = try String(contentsOf: url, encoding: .utf8)
        #expect(updatedContent == content)
    }

    // MARK: - appendSteps

    @Test("Phase format: appendSteps adds new lines to the file")
    func phaseFormatAppendSteps() async throws {
        let url = try makeTempFile(content: "## - [ ] Phase 1\n")
        defer { cleanup(url) }

        let source = MarkdownPipelineSource(fileURL: url, format: .phase)
        let newStep = CodeChangeStep(id: "new", description: "Phase 2", prompt: "Do phase 2")

        try await source.appendSteps([newStep])

        let updatedContent = try String(contentsOf: url, encoding: .utf8)
        #expect(updatedContent.contains("## - [ ] Phase 2"))
    }

    @Test("Task format: appendSteps adds new lines to the file")
    func taskFormatAppendSteps() async throws {
        let url = try makeTempFile(content: "- [ ] Task 1\n")
        defer { cleanup(url) }

        let source = MarkdownPipelineSource(fileURL: url, format: .task, appendCreatePRStep: false)
        let newStep = CodeChangeStep(id: "new", description: "Task 2", prompt: "Do task 2")

        try await source.appendSteps([newStep])

        let updatedContent = try String(contentsOf: url, encoding: .utf8)
        #expect(updatedContent.contains("- [ ] Task 2"))
    }
}
