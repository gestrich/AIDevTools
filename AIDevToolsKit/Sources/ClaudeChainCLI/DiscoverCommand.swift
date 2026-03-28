import ArgumentParser
import Foundation
import ClaudeChainInfrastructure
import ClaudeChainService

public struct DiscoverCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "discover",
        abstract: "Discover all refactor projects in the repository"
    )
    
    public init() {}
    
    public func run() throws {
        discoverProjects()
    }
}

private func discoverProjects() {
    print("Discovering refactor projects...")
    
    // Auto-detect base directory from environment or use default
    let baseDir = ProcessInfo.processInfo.environment["CLAUDECHAIN_PROJECT_DIR"] ?? "claude-chain"
    
    let projects = Project.findAll(baseDir: baseDir)
    let projectNames = projects.map { $0.name }
    
    if projectNames.isEmpty {
        print("No projects found")
    } else {
        print("\nFound \(projectNames.count) project(s):")
        for project in projectNames {
            print("  - \(project)")
        }
    }
    
    let projectsJSON: String
    do {
        let data = try JSONSerialization.data(withJSONObject: projectNames, options: [])
        projectsJSON = String(data: data, encoding: .utf8) ?? "[]"
    } catch {
        projectsJSON = "[]"
    }
    
    // Output for GitHub Actions
    let gh = GitHubActions()
    gh.writeOutput(name: "projects", value: projectsJSON)
    gh.writeOutput(name: "project_count", value: String(projectNames.count))
    
    print("\nProjects JSON: \(projectsJSON)")
}