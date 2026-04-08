import CLISDK
import Foundation
import GitSDK
import PipelineSDK

public struct WorktreeNode: PipelineNode {
    public static let nodeID: String = "worktree-node"
    public static let worktreePathKey = PipelineContextKey<String>("WorktreeNode.worktreePath")

    public let id: String = WorktreeNode.nodeID
    public let displayName: String = "Creating worktree"

    private let gitClient: GitClient
    private let options: WorktreeOptions

    public init(options: WorktreeOptions, gitClient: GitClient) {
        self.gitClient = gitClient
        self.options = options
    }

    public func run(
        context: PipelineContext,
        onProgress: @escaping @Sendable (PipelineNodeProgress) -> Void
    ) async throws -> PipelineContext {
        if FileManager.default.fileExists(atPath: options.destinationPath) {
            onProgress(.output("Reusing existing worktree at \(options.destinationPath)..."))
        } else if let basedOn = options.basedOn {
            onProgress(.output("Creating worktree at \(options.destinationPath)..."))
            do {
                try await gitClient.createWorktreeWithNewBranch(
                    branchName: options.branchName,
                    basedOn: basedOn,
                    destination: options.destinationPath,
                    workingDirectory: options.repoPath
                )
            } catch CLIClientError.executionFailed(_, _, let output) where output.contains("already exists") {
                try await gitClient.createWorktreeForExistingLocalBranch(
                    branchName: options.branchName,
                    destination: options.destinationPath,
                    workingDirectory: options.repoPath
                )
            }
        } else {
            onProgress(.output("Creating worktree at \(options.destinationPath)..."))
            try await gitClient.createWorktree(
                baseBranch: options.branchName,
                destination: options.destinationPath,
                workingDirectory: options.repoPath
            )
        }
        var updated = context
        updated[PipelineContext.workingDirectoryKey] = options.destinationPath
        updated[WorktreeNode.worktreePathKey] = options.destinationPath
        return updated
    }
}
