import PipelineService
import Testing

@Suite("WorktreeOptions")
struct WorktreeOptionsTests {

    @Test("stores branchName, destinationPath, and repoPath")
    func propertiesRoundTrip() {
        let options = WorktreeOptions(
            branchName: "feature-branch",
            destinationPath: "/tmp/worktrees/feature-branch",
            repoPath: "/path/to/repo"
        )

        #expect(options.branchName == "feature-branch")
        #expect(options.destinationPath == "/tmp/worktrees/feature-branch")
        #expect(options.repoPath == "/path/to/repo")
    }
}
