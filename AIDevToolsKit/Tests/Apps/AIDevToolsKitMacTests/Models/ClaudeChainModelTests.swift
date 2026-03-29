import AIOutputSDK
import ClaudeChainFeature
import Foundation
import ProviderRegistryService
import Testing

@testable import AIDevToolsKitMac

@Suite("ClaudeChainModel")
struct ClaudeChainModelTests {

    // MARK: - Helpers

    private func createTempRepoWithChain(
        projectName: String = "test-project",
        specContent: String
    ) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let projectDir = tempDir
            .appendingPathComponent("claude-chain")
            .appendingPathComponent(projectName)
        try FileManager.default.createDirectory(
            at: projectDir,
            withIntermediateDirectories: true
        )
        let specFile = projectDir.appendingPathComponent("spec.md")
        try specContent.write(to: specFile, atomically: true, encoding: .utf8)
        return tempDir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor private func makeModel() -> ClaudeChainModel {
        let registry = ProviderRegistry(providers: [StubAIClient()])
        return ClaudeChainModel(providerRegistry: registry)
    }

    // MARK: - loadChains state transitions

    @Test("initial state is idle")
    @MainActor func initialState() {
        // Arrange
        let model = makeModel()

        // Assert
        guard case .idle = model.state else {
            Issue.record("Expected .idle, got \(model.state)")
            return
        }
    }

    @Test("loadChains transitions to loadingChains immediately")
    @MainActor func loadChainsTransitionsToLoading() throws {
        // Arrange
        let repoPath = try createTempRepoWithChain(specContent: """
            # Spec

            ## Tasks

            - [x] Task 1 - Done
            - [ ] Task 2 - Pending
            """)
        defer { cleanup(repoPath) }
        let model = makeModel()

        // Act
        model.loadChains(for: repoPath)

        // Assert
        guard case .loadingChains = model.state else {
            Issue.record("Expected .loadingChains, got \(model.state)")
            return
        }
    }

    @Test("loadChains transitions to loaded with chain projects")
    @MainActor func loadChainsTransitionsToLoaded() async throws {
        // Arrange
        let repoPath = try createTempRepoWithChain(
            projectName: "my-chain",
            specContent: """
                # Spec

                ## Tasks

                - [x] Task 1 - Done
                - [x] Task 2 - Done
                - [ ] Task 3 - Pending
                """
        )
        defer { cleanup(repoPath) }
        let model = makeModel()

        // Act
        model.loadChains(for: repoPath)
        try await Task.sleep(for: .milliseconds(100))

        // Assert
        guard case .loaded(let projects) = model.state else {
            Issue.record("Expected .loaded, got \(model.state)")
            return
        }
        #expect(projects.count == 1)
        #expect(projects[0].name == "my-chain")
        #expect(projects[0].completedTasks == 2)
        #expect(projects[0].pendingTasks == 1)
        #expect(projects[0].totalTasks == 3)
    }

    @Test("loadChains returns empty array for repo without chains")
    @MainActor func loadChainsEmptyRepo() async throws {
        // Arrange
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        defer { cleanup(tempDir) }
        let model = makeModel()

        // Act
        model.loadChains(for: tempDir)
        try await Task.sleep(for: .milliseconds(100))

        // Assert
        guard case .loaded(let projects) = model.state else {
            Issue.record("Expected .loaded, got \(model.state)")
            return
        }
        #expect(projects.isEmpty)
    }

    @Test("loadChains discovers multiple chain projects")
    @MainActor func loadChainsMultipleProjects() async throws {
        // Arrange
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let chainDir = tempDir.appendingPathComponent("claude-chain")

        let spec = """
            # Spec

            ## Tasks

            - [ ] Task 1 - Do something
            """

        for name in ["alpha", "beta"] {
            let projectDir = chainDir.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: projectDir,
                withIntermediateDirectories: true
            )
            try spec.write(
                to: projectDir.appendingPathComponent("spec.md"),
                atomically: true,
                encoding: .utf8
            )
        }
        defer { cleanup(tempDir) }
        let model = makeModel()

        // Act
        model.loadChains(for: tempDir)
        try await Task.sleep(for: .milliseconds(100))

        // Assert
        guard case .loaded(let projects) = model.state else {
            Issue.record("Expected .loaded, got \(model.state)")
            return
        }
        #expect(projects.count == 2)
        let names = projects.map(\.name).sorted()
        #expect(names == ["alpha", "beta"])
    }

    // MARK: - executeChain state transitions

    @Test("executeChain transitions to executing immediately")
    @MainActor func executeChainTransitionsToExecuting() throws {
        // Arrange
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        defer { cleanup(tempDir) }
        let model = makeModel()

        // Act
        model.executeChain(projectName: "test", repoPath: tempDir)

        // Assert
        guard case .executing(let name, let status) = model.state else {
            Issue.record("Expected .executing, got \(model.state)")
            return
        }
        #expect(name == "test")
        #expect(status == "Starting...")
    }

    @Test("executeChain transitions to error for nonexistent project")
    @MainActor func executeChainErrorForMissingProject() async throws {
        // Arrange
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        defer { cleanup(tempDir) }
        let model = makeModel()

        // Act
        model.executeChain(projectName: "nonexistent", repoPath: tempDir)
        try await Task.sleep(for: .milliseconds(200))

        // Assert
        guard case .error(let error) = model.state else {
            Issue.record("Expected .error, got \(model.state)")
            return
        }
        #expect(error.localizedDescription.contains("No spec.md found"))
    }
}

// MARK: - Test Doubles

private struct StubAIClient: AIClient {
    let displayName = "Stub"
    let name = "stub"

    func getSessionDetails(sessionId: String, summary: String, lastModified: Date, workingDirectory: String) -> SessionDetails? {
        nil
    }

    func listSessions(workingDirectory: String) async -> [ChatSession] {
        []
    }

    func loadSessionMessages(sessionId: String, workingDirectory: String) async -> [ChatSessionMessage] {
        []
    }

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
