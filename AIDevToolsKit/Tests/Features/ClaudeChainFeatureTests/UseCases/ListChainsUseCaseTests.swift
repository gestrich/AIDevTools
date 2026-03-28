import ClaudeChainFeature
import ClaudeChainSDK
import ClaudeChainService
import Foundation
import Testing

@Suite("ListChainsUseCase")
struct ListChainsUseCaseTests {

    let demoRepoPath = URL(fileURLWithPath: "/Users/bill/Developer/personal/claude-chain-demo")

    @Test("discovers chains from demo repo with absolute paths")
    func discoversChains() throws {
        let useCase = ListChainsUseCase()
        let options = ListChainsUseCase.Options(repoPath: demoRepoPath)
        let chains = try useCase.run(options: options)

        #expect(chains.count == 2)
        let names = chains.map(\.name).sorted()
        #expect(names == ["async-test", "hello-world"])
    }

    @Test("hello-world chain has correct task counts")
    func helloWorldTaskCounts() throws {
        let useCase = ListChainsUseCase()
        let options = ListChainsUseCase.Options(repoPath: demoRepoPath)
        let chains = try useCase.run(options: options)

        let helloWorld = try #require(chains.first(where: { $0.name == "hello-world" }))
        #expect(helloWorld.totalTasks == 5)
        #expect(helloWorld.completedTasks == 4)
        #expect(helloWorld.pendingTasks == 1)
    }

    @Test("async-test chain has correct task counts")
    func asyncTestTaskCounts() throws {
        let useCase = ListChainsUseCase()
        let options = ListChainsUseCase.Options(repoPath: demoRepoPath)
        let chains = try useCase.run(options: options)

        let asyncTest = try #require(chains.first(where: { $0.name == "async-test" }))
        #expect(asyncTest.totalTasks == 4)
        #expect(asyncTest.completedTasks == 0)
        #expect(asyncTest.pendingTasks == 4)
    }

    @Test("spec paths use absolute paths")
    func specPathsAreAbsolute() throws {
        let useCase = ListChainsUseCase()
        let options = ListChainsUseCase.Options(repoPath: demoRepoPath)
        let chains = try useCase.run(options: options)

        for chain in chains {
            #expect(chain.specPath.hasPrefix("/"))
            #expect(FileManager.default.fileExists(atPath: chain.specPath))
        }
    }

    @Test("returns empty array for repo without claude-chain directory")
    func emptyForMissingDir() throws {
        let useCase = ListChainsUseCase()
        let options = ListChainsUseCase.Options(repoPath: URL(fileURLWithPath: "/tmp"))
        let chains = try useCase.run(options: options)

        #expect(chains.isEmpty)
    }
}
