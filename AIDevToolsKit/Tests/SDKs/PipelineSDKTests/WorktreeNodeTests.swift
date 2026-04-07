import GitSDK
import PipelineService
import Testing

@Suite("WorktreeNode")
struct WorktreeNodeTests {

    private func makeNode() -> WorktreeNode {
        let options = WorktreeOptions(
            branchName: "plan-abc123",
            destinationPath: "/tmp/worktrees/plan-abc123",
            repoPath: "/tmp/repo"
        )
        return WorktreeNode(options: options, gitClient: GitClient())
    }

    @Test("id is worktree-node")
    func nodeId() {
        let node = makeNode()
        #expect(node.id == "worktree-node")
    }

    @Test("displayName is Creating worktree")
    func nodeDisplayName() {
        let node = makeNode()
        #expect(node.displayName == "Creating worktree")
    }

    @Test("worktreePathKey name is WorktreeNode.worktreePath")
    func worktreePathKeyIdentifier() {
        #expect(WorktreeNode.worktreePathKey.name == "WorktreeNode.worktreePath")
    }
}
