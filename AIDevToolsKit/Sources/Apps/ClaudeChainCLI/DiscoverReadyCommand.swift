import ArgumentParser
import ClaudeChainService
import ClaudeChainSDK
import ClaudeChainFeature
import Foundation

public struct DiscoverReadyCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "discover-ready",
        abstract: "Discover projects with capacity and available tasks"
    )
    
    public init() {}
    
    public func run() throws {
        print("========================================================================")
        print("ClaudeChain Discovery Mode")
        print("========================================================================")
        print("")
        print("🔍 Finding all projects with capacity and available tasks...")
        print("")
        
        // Initialize GitHub Actions helper
        let gh = GitHubActions()
        
        // Get repository from environment
        guard let repo = ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"], !repo.isEmpty else {
            print("Error: GITHUB_REPOSITORY environment variable not set")
            gh.writeOutput(name: "projects", value: "[]")
            gh.writeOutput(name: "project_count", value: "0")
            throw ExitCode.failure
        }
        
        // Discover all projects
        let allProjects = Project.findAll()
        
        if allProjects.isEmpty {
            print("No refactor projects found")
            print("")
            gh.writeOutput(name: "projects", value: "[]")
            gh.writeOutput(name: "project_count", value: "0")
            return
        }
        
        // Check each project for capacity and tasks
        var readyProjects: [String] = []
        
        for project in allProjects {
            print("Checking project: \(project.name)")
            if checkProjectReady(projectName: project.name, repo: repo) {
                readyProjects.append(project.name)
            }
        }
        
        // Output results
        if readyProjects.isEmpty {
            print("")
            print("No projects have available capacity and tasks")
            print("")
            let projectsJson = "[]"
            gh.writeOutput(name: "projects", value: projectsJson)
            gh.writeOutput(name: "project_count", value: "0")
        } else {
            print("")
            print("========================================================================")
            print("Found \(readyProjects.count) project(s) ready for work:")
            for project in readyProjects {
                print("  - \(project)")
            }
            print("========================================================================")
            print("")
            
            let encoder = JSONEncoder()
            let projectsJsonData = try encoder.encode(readyProjects)
            let projectsJson = String(data: projectsJsonData, encoding: .utf8) ?? "[]"
            
            gh.writeOutput(name: "projects", value: projectsJson)
            gh.writeOutput(name: "project_count", value: "\(readyProjects.count)")
        }
    }
    
    /// Orchestrate project readiness check using Service Layer classes.
    ///
    /// This function instantiates services and coordinates their operations but
    /// does not implement business logic directly. Follows Service Layer pattern.
    ///
    /// A project is ready if:
    /// 1. spec.md exists (required)
    /// 2. Spec format is valid (contains checklist items)
    /// 3. Has capacity (only 1 open PR per project allowed)
    /// 4. Has available tasks
    ///
    /// Configuration is optional - projects without configuration.yml use default settings.
    ///
    /// - Parameters:
    ///   - projectName: Name of the project to check
    ///   - repo: GitHub repository (owner/name)
    /// - Returns: True if project is ready for work, False otherwise
    private func checkProjectReady(projectName: String, repo: String) -> Bool {
        do {
            // Create Project domain model
            let project = Project(name: projectName)
            
            // Check if spec.md exists (required)
            if !FileManager.default.fileExists(atPath: project.specPath) {
                print("  ⏭️  No spec.md found")
                return false
            }
            
            // Validate spec format
            do {
                _ = try Config.validateSpecFormat(specFile: project.specPath)
            } catch {
                print("  ⏭️  Invalid spec format: \(error.localizedDescription)")
                return false
            }
            
            // Use single 'claudechain' label for all projects
            let label = "claudechain"
            
            // Load configuration (optional - uses defaults if not found)
            let projectConfig: ProjectConfiguration
            if FileManager.default.fileExists(atPath: project.configPath) {
                let configContent = try String(contentsOfFile: project.configPath, encoding: .utf8)
                projectConfig = try ProjectConfiguration.fromYAMLString(project: project, yamlContent: configContent)
            } else {
                projectConfig = ProjectConfiguration.default(project: project)
            }
            
            // Initialize services
            let prService = PRService(repo: repo)
            let assigneeService = AssigneeService(repo: repo, prService: prService)
            let taskService = TaskService(repo: repo, prService: prService)
            
            // Check capacity against project's maxOpenPRs setting
            let capacityResult = assigneeService.checkCapacity(config: projectConfig, label: label, project: projectName)
            
            if !capacityResult.hasCapacity {
                print("  ⏭️  Project at capacity (\(capacityResult.maxOpenPRs) open PR limit)")
                return false
            }
            
            // Load spec and check for available tasks
            let specContent = try String(contentsOfFile: project.specPath, encoding: .utf8)
            let spec = SpecContent(project: project, content: specContent)
            
            // Get in-progress tasks
            let inProgressHashes = taskService.getInProgressTasks(label: label, project: projectName)
            let nextTask = taskService.findNextAvailableTask(spec: spec, skipHashes: inProgressHashes)
            
            if nextTask == nil {
                print("  ⏭️  No available tasks")
                return false
            }
            
            // Get stats for logging
            let uncompleted = spec.pendingTasks
            let openPrs = capacityResult.openPRs.count
            
            print("  ✅ Ready for work (\(openPrs)/1 PRs, \(uncompleted) tasks remaining)")
            return true
            
        } catch {
            print("  ❌ Error checking project: \(error.localizedDescription)")
            return false
        }
    }
}