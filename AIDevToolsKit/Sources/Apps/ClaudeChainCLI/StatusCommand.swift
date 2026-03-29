import ArgumentParser
import ClaudeChainFeature
import Foundation

public struct StatusCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show chain project status and task progress"
    )

    @Option(name: .long, help: "Path to the repository containing claude-chain/")
    public var repoPath: String?

    @Argument(help: "Project name to show details for (optional, shows all if omitted)")
    public var project: String?

    public init() {}

    public func run() throws {
        let path: String
        if let repoPath {
            path = repoPath
        } else if let envPath = ProcessInfo.processInfo.environment["CLAUDECHAIN_REPO_PATH"] {
            path = envPath
        } else {
            path = FileManager.default.currentDirectoryPath
        }

        let repoURL = URL(fileURLWithPath: path)
        let useCase = ListChainsUseCase()
        let projects = try useCase.run(options: .init(repoPath: repoURL))

        if projects.isEmpty {
            print("No chain projects found in \(repoURL.appendingPathComponent("claude-chain").path)")
            return
        }

        if let projectName = project {
            guard let matched = projects.first(where: { $0.name == projectName }) else {
                print("Project '\(projectName)' not found. Available projects:")
                for p in projects.sorted(by: { $0.name < $1.name }) {
                    print("  \(p.name)")
                }
                throw ExitCode.failure
            }
            printProjectDetail(matched)
        } else {
            printProjectList(projects)
        }
    }

    private func printProjectList(_ projects: [ChainProject]) {
        let sorted = projects.sorted { $0.name < $1.name }
        let maxNameLen = sorted.map(\.name.count).max() ?? 0

        for project in sorted {
            let padded = project.name.padding(toLength: maxNameLen, withPad: " ", startingAt: 0)
            let bar = progressBar(completed: project.completedTasks, total: project.totalTasks)
            let counts = "\(project.completedTasks)/\(project.totalTasks) tasks completed"
            let pending = project.pendingTasks > 0 ? " · \(project.pendingTasks) pending" : ""
            print("  \(padded)  \(bar)  \(counts)\(pending)")
        }

        let totalCompleted = projects.reduce(0) { $0 + $1.completedTasks }
        let totalAll = projects.reduce(0) { $0 + $1.totalTasks }
        print("\n\(projects.count) project(s), \(totalCompleted)/\(totalAll) total tasks completed")
    }

    private func printProjectDetail(_ project: ChainProject) {
        print(project.name)
        print("Progress  \(project.completedTasks)/\(project.totalTasks) tasks completed")
        print()
        print("Tasks")

        for task in project.tasks {
            let icon = task.isCompleted ? "✓" : "○"
            print("  \(icon) \(task.description)")
        }
    }

    private func progressBar(completed: Int, total: Int, width: Int = 20) -> String {
        guard total > 0 else { return "[\(String(repeating: "-", count: width))]" }
        let filled = Int(Double(completed) / Double(total) * Double(width))
        let empty = width - filled
        return "[\(String(repeating: "█", count: filled))\(String(repeating: "░", count: empty))]"
    }
}
