import ArgumentParser
import Foundation
import GitSDK
import WorktreeFeature

struct WorktreeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "worktree",
        abstract: "Manage git worktrees",
        subcommands: [AddWorktree.self, ListWorktrees.self, RemoveWorktree.self]
    )
}

struct AddWorktree: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a new worktree"
    )

    @Argument(help: "Path to the repository")
    var repoPath: String

    @Argument(help: "Destination path for the new worktree")
    var destination: String

    @Option(name: .long, help: "Branch name to create or checkout")
    var branch: String

    func run() async throws {
        let gitClient = GitClient()
        let useCase = AddWorktreeUseCase(gitClient: gitClient, listUseCase: ListWorktreesUseCase(gitClient: gitClient))
        try await useCase.execute(repoPath: repoPath, destination: destination, branch: branch)
        print("Added worktree at \(destination) on branch \(branch).")
    }
}

struct ListWorktrees: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List worktrees for a repository"
    )

    @Argument(help: "Path to the repository")
    var repoPath: String

    func run() async throws {
        let useCase = ListWorktreesUseCase(gitClient: GitClient())
        let statuses = try await useCase.execute(repoPath: repoPath)
        if statuses.isEmpty {
            print("No worktrees found.")
            return
        }
        for status in statuses {
            var line = "\(status.name)  \(status.branch)  \(status.path)"
            if status.isMain { line += "  [main]" }
            if status.hasUncommittedChanges { line += "  [dirty]" }
            print(line)
        }
    }
}

struct RemoveWorktree: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a worktree"
    )

    @Argument(help: "Path to the repository")
    var repoPath: String

    @Argument(help: "Path of the worktree to remove")
    var worktreePath: String

    @Flag(name: .long, help: "Force removal even with uncommitted changes")
    var force: Bool = false

    func run() async throws {
        let gitClient = GitClient()
        let useCase = RemoveWorktreeUseCase(gitClient: gitClient, listUseCase: ListWorktreesUseCase(gitClient: gitClient))
        try await useCase.execute(repoPath: repoPath, worktreePath: worktreePath, force: force)
        print("Removed worktree at \(worktreePath).")
    }
}
