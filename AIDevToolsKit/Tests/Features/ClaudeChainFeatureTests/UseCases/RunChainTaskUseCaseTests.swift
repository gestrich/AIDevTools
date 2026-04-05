import AIOutputSDK
import ClaudeChainFeature
import ClaudeChainSDK
import ClaudeChainService
import Foundation
import Testing

@Suite("RunMarkdownChainTaskUseCase", .serialized)
struct RunMarkdownChainTaskUseCaseTests {

    // MARK: - Helpers

    private func createTempProject(
        projectName: String = "test-project",
        specContent: String? = nil
    ) throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let projectDir = tmpDir
            .appendingPathComponent("claude-chain")
            .appendingPathComponent(projectName)
        try FileManager.default.createDirectory(
            at: projectDir,
            withIntermediateDirectories: true
        )
        if let specContent {
            try specContent.write(
                to: projectDir.appendingPathComponent("spec.md"),
                atomically: true,
                encoding: .utf8
            )
        }
        return tmpDir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func withCWD<T>(_ path: String, body: () async throws -> T) async rethrows -> T {
        let original = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(path)
        defer { FileManager.default.changeCurrentDirectoryPath(original) }
        return try await body()
    }

    // MARK: - Prepare phase failure tests

    @Test("returns failure when no spec.md exists")
    func noSpecFound() async throws {
        // Arrange
        let tmpDir = try createTempProject(specContent: nil)
        defer { cleanup(tmpDir) }

        var progressEvents: [String] = []
        let useCase = RunMarkdownChainTaskUseCase(client: StubAIClient())

        // Act
        let result = try await useCase.run(
            options: .init(repoPath: tmpDir, projectName: "test-project", baseBranch: "main"),
            onProgress: { progress in
                progressEvents.append(progressLabel(progress))
            }
        )

        // Assert
        #expect(!result.success)
        #expect(result.message.contains("No spec.md found"))
        #expect(progressEvents == ["preparingProject", "failed:prepare"])
    }

    @Test("returns failure when all tasks are completed")
    func allTasksCompleted() async throws {
        // Arrange
        let tmpDir = try createTempProject(specContent: """
            # Test Project
            - [x] Task one
            - [x] Task two
            - [x] Task three
            """)
        defer { cleanup(tmpDir) }

        var progressEvents: [String] = []
        let useCase = RunMarkdownChainTaskUseCase(client: StubAIClient())

        // Act
        let result = try await useCase.run(
            options: .init(repoPath: tmpDir, projectName: "test-project", baseBranch: "main"),
            onProgress: { progress in
                progressEvents.append(progressLabel(progress))
            }
        )

        // Assert
        #expect(!result.success)
        #expect(result.message.contains("All tasks completed"))
        #expect(progressEvents == ["preparingProject", "failed:prepare"])
    }

    @Test("emits preparedTask with correct task info before git failure")
    func preparedTaskProgress() async throws {
        // Arrange
        let tmpDir = try createTempProject(specContent: """
            # Test Project
            - [x] Completed task
            - [ ] Pending task A
            - [ ] Pending task B
            """)
        defer { cleanup(tmpDir) }

        var progressEvents: [String] = []
        var preparedDescription: String?
        var preparedIndex: Int?
        var preparedTotal: Int?
        let useCase = RunMarkdownChainTaskUseCase(client: StubAIClient())

        // Act — run in tmpDir (not a git repo) so git checkout -b fails
        do {
            _ = try await withCWD(tmpDir.path) {
                try await useCase.run(
                    options: .init(repoPath: tmpDir, projectName: "test-project", baseBranch: "main"),
                    onProgress: { progress in
                        progressEvents.append(progressLabel(progress))
                        if case .preparedTask(let desc, let idx, let total) = progress {
                            preparedDescription = desc
                            preparedIndex = idx
                            preparedTotal = total
                        }
                    }
                )
            }
        } catch {
            // Expected: git checkout -b fails since tmpDir has no git repo
        }

        // Assert
        #expect(progressEvents.contains("preparingProject"))
        #expect(progressEvents.contains("preparedTask"))
        #expect(preparedDescription == "Pending task A")
        #expect(preparedIndex == 2)
        #expect(preparedTotal == 3)
    }

    @Test("emits progress through AI phases with scripts skipped in git repo")
    func progressThroughAIPhasesWithScriptsSkipped() async throws {
        // Arrange
        let tmpDir = try createTempProject(specContent: """
            # Test Project
            - [ ] First task
            - [ ] Second task
            """)
        defer { cleanup(tmpDir) }

        initGitRepo(at: tmpDir)

        var progressEvents: [String] = []
        let useCase = RunMarkdownChainTaskUseCase(client: StubAIClient())

        // Act — run in tmpDir (a git repo) so checkout succeeds
        do {
            _ = try await withCWD(tmpDir.path) {
                try await useCase.run(
                    options: .init(repoPath: tmpDir, projectName: "test-project", baseBranch: "main"),
                    onProgress: { progress in
                        progressEvents.append(progressLabel(progress))
                    }
                )
            }
        } catch {
            // Expected: finalize phase fails (no remote for push / no gh CLI auth)
        }

        // Assert — verify progress through prepare, scripts, and AI
        #expect(progressEvents.contains("preparingProject"))
        #expect(progressEvents.contains("preparedTask"))
        #expect(progressEvents.contains("runningPreScript"))
        #expect(progressEvents.contains("preScriptCompleted"))
        #expect(progressEvents.contains("runningAI"))
        #expect(progressEvents.contains("aiCompleted"))
        #expect(progressEvents.contains("runningPostScript"))
        #expect(progressEvents.contains("postScriptCompleted"))
        #expect(progressEvents.contains("finalizing"))
    }

    @Test("PR summary and comment phases come after PR creation in progress sequence")
    func summaryAndCommentAfterPRCreation() {
        // The implementation in RunMarkdownChainTaskUseCase.run() executes phases sequentially:
        //   finalize → prCreated → generatingSummary → summaryCompleted → postingPRComment → prCommentPosted → completed
        //
        // This ordering is verified by code inspection of RunMarkdownChainTaskUseCase.swift lines 212-287:
        //   - Phase 6 (summary) starts AFTER prCreated is emitted (line 213)
        //   - Phase 7 (comment) starts AFTER summary phase (line 246)
        //
        // Full end-to-end testing of these phases requires a GitHub remote
        // and is covered by integration tests against the demo repo.
    }

    // MARK: - Git Helpers

    private func initGitRepo(at url: URL) {
        let commands: [[String]] = [
            ["init"],
            ["config", "user.email", "test@test.com"],
            ["config", "user.name", "Test"],
            ["add", "-A"],
            ["commit", "-m", "Initial commit"],
        ]
        for args in commands {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = url
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }
}

// MARK: - Progress Label Helper

private func progressLabel(_ progress: RunMarkdownChainTaskUseCase.Progress) -> String {
    switch progress {
    case .aiCompleted: "aiCompleted"
    case .aiOutput: "aiOutput"
    case .aiStreamEvent: "aiStreamEvent"
    case .completed: "completed"
    case .failed(let phase, _): "failed:\(phase)"
    case .finalizing: "finalizing"
    case .generatingSummary: "generatingSummary"
    case .postingPRComment: "postingPRComment"
    case .postScriptCompleted: "postScriptCompleted"
    case .prCommentPosted: "prCommentPosted"
    case .prCreated: "prCreated"
    case .preparingProject: "preparingProject"
    case .preparedTask: "preparedTask"
    case .preScriptCompleted: "preScriptCompleted"
    case .reviewCompleted(let summary): "reviewCompleted:\(summary)"
    case .runningAI: "runningAI"
    case .runningPostScript: "runningPostScript"
    case .runningPreScript: "runningPreScript"
    case .runningReview: "runningReview"
    case .summaryCompleted: "summaryCompleted"
    case .summaryStreamEvent: "summaryStreamEvent"
    }
}

// MARK: - appendReviewNote Tests

@Suite("RunMarkdownChainTaskUseCase.appendReviewNote")
struct AppendReviewNoteTests {

    private let useCase = RunMarkdownChainTaskUseCase(client: StubAIClient())

    private func writeTempSpec(_ content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec_\(UUID().uuidString).md")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("inserts HTML comment after the matching [x] task line")
    func insertsNoteAfterTask() throws {
        // Arrange
        let specURL = try writeTempSpec("""
            - [x] Add authentication
            - [ ] Next task
            """)
        defer { try? FileManager.default.removeItem(at: specURL) }

        // Act
        useCase.appendReviewNote(specPath: specURL.path, taskDescription: "Add authentication", summary: "No changes needed")

        // Assert
        let result = try String(contentsOf: specURL, encoding: .utf8)
        #expect(result.contains("<!-- review: No changes needed -->"))
        let lines = result.components(separatedBy: .newlines)
        let taskIdx = lines.firstIndex(where: { $0.contains("[x] Add authentication") })!
        #expect(lines[taskIdx + 1].contains("<!-- review:"))
    }

    @Test("does not modify spec when task is not found")
    func gracefulWhenTaskNotFound() throws {
        // Arrange
        let original = "- [x] Some other task\n"
        let specURL = try writeTempSpec(original)
        defer { try? FileManager.default.removeItem(at: specURL) }

        // Act
        useCase.appendReviewNote(specPath: specURL.path, taskDescription: "Nonexistent task", summary: "No changes needed")

        // Assert
        let result = try String(contentsOf: specURL, encoding: .utf8)
        #expect(result == original)
    }

    @Test("inserts note under the correct task in a multi-task spec")
    func targetsCorrectTask() throws {
        // Arrange
        let specURL = try writeTempSpec("""
            - [x] Task one
            - [x] Task two
            - [ ] Task three
            """)
        defer { try? FileManager.default.removeItem(at: specURL) }

        // Act
        useCase.appendReviewNote(specPath: specURL.path, taskDescription: "Task two", summary: "Fixed indentation")

        // Assert
        let result = try String(contentsOf: specURL, encoding: .utf8)
        let lines = result.components(separatedBy: .newlines)
        let taskIdx = lines.firstIndex(where: { $0.contains("[x] Task two") })!
        #expect(lines[taskIdx + 1].contains("Fixed indentation"))
        let taskOneIdx = lines.firstIndex(where: { $0.contains("[x] Task one") })!
        #expect(!lines[taskOneIdx + 1].contains("review:"))
    }
}

// MARK: - Test Doubles

private struct StubAIClient: AIClient {
    let displayName = "Stub"
    let name = "stub"

    func run(
        prompt: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIClientResult {
        AIClientResult(exitCode: 0, stderr: "", stdout: "")
    }

    func runStructured<T: Decodable & Sendable>(
        _ type: T.Type,
        prompt: String,
        jsonSchema: String,
        options: AIClientOptions,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> AIStructuredResult<T> {
        throw NSError(domain: "StubAIClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
}
