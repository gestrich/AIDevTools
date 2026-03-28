import ClaudeChainFeature
import ClaudeChainSDK
import ClaudeChainService
import Foundation
import Testing

@Suite("ExecuteChainUseCase - spec verification")
struct ExecuteChainUseCaseSpecTests {

    let demoRepoPath = URL(fileURLWithPath: "/Users/bill/Developer/personal/claude-chain-demo")

    @Test("hello-world next available task is task 5")
    func nextAvailableTask() throws {
        let chainDir = demoRepoPath.appendingPathComponent("claude-chain").path
        let project = Project(
            name: "hello-world",
            basePath: (chainDir as NSString).appendingPathComponent("hello-world")
        )
        let repository = ProjectRepository(repo: "")
        let spec = try #require(try repository.loadLocalSpec(project: project))

        let nextTask = try #require(spec.getNextAvailableTask())
        #expect(nextTask.description == "Create hello-world-5.txt")
        #expect(nextTask.index == 5)
        #expect(!nextTask.isCompleted)
    }

    @Test("async-test next available task is task 1")
    func asyncTestNextTask() throws {
        let chainDir = demoRepoPath.appendingPathComponent("claude-chain").path
        let project = Project(
            name: "async-test",
            basePath: (chainDir as NSString).appendingPathComponent("async-test")
        )
        let repository = ProjectRepository(repo: "")
        let spec = try #require(try repository.loadLocalSpec(project: project))

        let nextTask = try #require(spec.getNextAvailableTask())
        #expect(nextTask.description.contains("task-1.txt"))
        #expect(nextTask.index == 1)
    }

    @Test("branch name format is correct")
    func branchNameFormat() throws {
        let chainDir = demoRepoPath.appendingPathComponent("claude-chain").path
        let project = Project(
            name: "hello-world",
            basePath: (chainDir as NSString).appendingPathComponent("hello-world")
        )
        let repository = ProjectRepository(repo: "")
        let spec = try #require(try repository.loadLocalSpec(project: project))
        let task = try #require(spec.getNextAvailableTask())

        let branchName = PRService.formatBranchName(projectName: "hello-world", taskHash: task.taskHash)
        #expect(branchName.hasPrefix("claude-chain-hello-world-"))
        #expect(branchName.count == "claude-chain-hello-world-".count + 8)

        let parsed = Project.fromBranchName(branchName)
        #expect(parsed?.name == "hello-world")
    }

    @Test("returns failure for nonexistent project")
    func nonexistentProject() async throws {
        let useCase = ExecuteChainUseCase()
        let result = try await useCase.run(options: .init(
            repoPath: demoRepoPath,
            projectName: "nonexistent"
        ))
        #expect(!result.success)
        #expect(result.message.contains("No spec.md found"))
    }
}
