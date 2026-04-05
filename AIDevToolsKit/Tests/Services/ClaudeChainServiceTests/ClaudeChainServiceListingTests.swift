import AIOutputSDK
import ClaudeChainFeature
import ClaudeChainService
import Foundation
import Testing

// MARK: - Helpers

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
        throw NSError(domain: "StubAIClient", code: 1)
    }
}

private struct StubChainProjectSource: ChainProjectSource {
    let result: ChainListResult

    func listChains() async throws -> ChainListResult { result }
}

private struct ThrowingChainProjectSource: ChainProjectSource {
    func listChains() async throws -> ChainListResult {
        throw NSError(domain: "TestError", code: 1)
    }
}

private func makeSpecProject(name: String, specPath: String) -> ChainProject {
    ChainProject(name: name, specPath: specPath, completedTasks: 0, pendingTasks: 1, totalTasks: 1)
}

private func makeSweepProject(name: String, specPath: String) -> ChainProject {
    ChainProject(name: name, specPath: specPath, completedTasks: 0, pendingTasks: 1, totalTasks: 1, kindBadge: "sweep")
}

// MARK: - listChains(source:kind:) tests

@Suite("ClaudeChainService.listChains")
struct ClaudeChainServiceListChainsTests {

    @Test("local source returns all projects")
    func localSourceReturnsAllProjects() async throws {
        let projects = [makeSpecProject(name: "alpha", specPath: "/repo/claude-chain/alpha/spec.md")]
        let service = ClaudeChainService(
            client: StubAIClient(),
            localSource: StubChainProjectSource(result: ChainListResult(projects: projects))
        )

        let result = try await service.listChains(source: .local)

        #expect(result.projects.count == 1)
        #expect(result.projects.first?.name == "alpha")
    }

    @Test("remote source returns all projects")
    func remoteSourceReturnsAllProjects() async throws {
        let projects = [makeSpecProject(name: "beta", specPath: "/repo/claude-chain/beta/spec.md")]
        let service = ClaudeChainService(
            client: StubAIClient(),
            localSource: StubChainProjectSource(result: ChainListResult(projects: [])),
            remoteSource: StubChainProjectSource(result: ChainListResult(projects: projects))
        )

        let result = try await service.listChains(source: .remote)

        #expect(result.projects.count == 1)
        #expect(result.projects.first?.name == "beta")
    }

    @Test("kind .spec filters out sweep projects")
    func specKindFiltersOutSweepProjects() async throws {
        let projects = [
            makeSpecProject(name: "spec-project", specPath: "/repo/claude-chain/spec-project/spec.md"),
            makeSweepProject(name: "sweep-project", specPath: "/repo/claude-chain-sweep/sweep-project/spec.md"),
        ]
        let service = ClaudeChainService(
            client: StubAIClient(),
            localSource: StubChainProjectSource(result: ChainListResult(projects: projects))
        )

        let result = try await service.listChains(source: .local, kind: .spec)

        #expect(result.projects.count == 1)
        #expect(result.projects.first?.name == "spec-project")
    }

    @Test("kind .sweep filters out spec projects")
    func sweepKindFiltersOutSpecProjects() async throws {
        let projects = [
            makeSpecProject(name: "spec-project", specPath: "/repo/claude-chain/spec-project/spec.md"),
            makeSweepProject(name: "sweep-project", specPath: "/repo/claude-chain-sweep/sweep-project/spec.md"),
        ]
        let service = ClaudeChainService(
            client: StubAIClient(),
            localSource: StubChainProjectSource(result: ChainListResult(projects: projects))
        )

        let result = try await service.listChains(source: .local, kind: .sweep)

        #expect(result.projects.count == 1)
        #expect(result.projects.first?.name == "sweep-project")
    }

    @Test("kind .all returns every project")
    func allKindReturnsEveryProject() async throws {
        let projects = [
            makeSpecProject(name: "spec-project", specPath: "/repo/claude-chain/spec-project/spec.md"),
            makeSweepProject(name: "sweep-project", specPath: "/repo/claude-chain-sweep/sweep-project/spec.md"),
        ]
        let service = ClaudeChainService(
            client: StubAIClient(),
            localSource: StubChainProjectSource(result: ChainListResult(projects: projects))
        )

        let result = try await service.listChains(source: .local, kind: .all)

        #expect(result.projects.count == 2)
    }

    @Test("missing local source throws")
    func missingLocalSourceThrows() async throws {
        let service = ClaudeChainService(client: StubAIClient())

        await #expect(throws: Error.self) {
            try await service.listChains(source: .local)
        }
    }

    @Test("missing remote source throws")
    func missingRemoteSourceThrows() async throws {
        let service = ClaudeChainService(
            client: StubAIClient(),
            localSource: StubChainProjectSource(result: ChainListResult(projects: []))
        )

        await #expect(throws: Error.self) {
            try await service.listChains(source: .remote)
        }
    }
}

// MARK: - detectLocalProjects(fromChangedPaths:) tests

@Suite("ClaudeChainService.detectLocalProjects")
struct ClaudeChainServiceDetectLocalProjectsTests {

    @Test("returns projects whose specPath appears in changed paths")
    func returnsMatchingProjects() async throws {
        let specPath = "/repo/claude-chain/my-project/spec.md"
        let projects = [makeSpecProject(name: "my-project", specPath: specPath)]
        let service = ClaudeChainService(
            client: StubAIClient(),
            localSource: StubChainProjectSource(result: ChainListResult(projects: projects))
        )

        let detected = try await service.detectLocalProjects(fromChangedPaths: [specPath])

        #expect(detected.count == 1)
        #expect(detected.first?.name == "my-project")
    }

    @Test("returns empty when no changed paths match a spec")
    func returnsEmptyWhenNoMatch() async throws {
        let projects = [makeSpecProject(name: "my-project", specPath: "/repo/claude-chain/my-project/spec.md")]
        let service = ClaudeChainService(
            client: StubAIClient(),
            localSource: StubChainProjectSource(result: ChainListResult(projects: projects))
        )

        let detected = try await service.detectLocalProjects(fromChangedPaths: ["/repo/some/other/file.swift"])

        #expect(detected.isEmpty)
    }

    @Test("returns projects sorted by name")
    func returnsSortedByName() async throws {
        let projects = [
            makeSpecProject(name: "zebra", specPath: "/repo/claude-chain/zebra/spec.md"),
            makeSpecProject(name: "alpha", specPath: "/repo/claude-chain/alpha/spec.md"),
        ]
        let service = ClaudeChainService(
            client: StubAIClient(),
            localSource: StubChainProjectSource(result: ChainListResult(projects: projects))
        )

        let detected = try await service.detectLocalProjects(fromChangedPaths: [
            "/repo/claude-chain/zebra/spec.md",
            "/repo/claude-chain/alpha/spec.md",
        ])

        #expect(detected.map(\.name) == ["alpha", "zebra"])
    }
}
