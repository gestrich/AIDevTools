import ClaudeChainService
import ClaudeChainSDK
import Foundation
import GitSDK
import Logging

public struct AutoStartService {

    private let logger = Logger(label: "AutoStartService")
    private let repo: String
    private let prService: PRService
    private let autoStartEnabled: Bool
    private let gitClient: GitClient
    
    /**
     * Initialize the auto-start service
     *
     * Args:
     *     repo: GitHub repository (owner/name)
     *     prService: PRService instance for PR operations
     *     autoStartEnabled: Whether auto-start is enabled (default: true)
     */
    public init(repo: String, prService: PRService, autoStartEnabled: Bool = true, gitClient: GitClient = GitClient()) {
        self.repo = repo
        self.prService = prService
        self.autoStartEnabled = autoStartEnabled
        self.gitClient = gitClient
    }
    
    // MARK: - Public API methods
    
    public func detectChangedProjects(refBefore: String, refAfter: String, specPattern: String = ClaudeChainConstants.specPathPattern, workingDirectory: String = FileManager.default.currentDirectoryPath) async throws -> [AutoStartProject] {
        // Identify projects with spec.md changes between two git references
        //
        // Args:
        //     refBefore: Git reference for the before state (e.g., commit SHA)
        //     refAfter: Git reference for the after state (e.g., commit SHA)
        //     specPattern: File pattern to match spec files (default: "claude-chain/*/spec.md")
        //
        // Returns:
        //     List of AutoStartProject domain models representing changed projects
        //
        // Examples:
        //     let service = AutoStartService("owner/repo", prService)
        //     let projects = service.detectChangedProjects("abc123", "def456")
        //     projects[0].name  // "my-project"
        //     projects[0].changeType  // ProjectChangeType.added
        var changedProjects: [AutoStartProject] = []

        do {
            try await gitClient.ensureRefAvailable(ref: refBefore, workingDirectory: workingDirectory)
            try await gitClient.ensureRefAvailable(ref: refAfter, workingDirectory: workingDirectory)
        } catch {
            logger.warning("Failed to ensure git refs are available: \(error)")
        }

        // Detect added or modified spec files
        do {
            let changedFiles = try await gitClient.diffChangedFiles(ref1: refBefore, ref2: refAfter, pattern: specPattern, workingDirectory: workingDirectory)
            for filePath in changedFiles {
                let projectName = MarkdownClaudeChainSource.matchesSpecPath(filePath) ?? SweepClaudeChainSource.matchesSpecPath(filePath)
                if let projectName {
                    changedProjects.append(
                        AutoStartProject(
                            name: projectName,
                            changeType: .modified,
                            specPath: filePath
                        )
                    )
                }
            }
        } catch {
            logger.warning("Failed to detect changed files: \(error)")
        }

        // Detect deleted spec files
        do {
            let deletedFiles = try await gitClient.diffDeletedFiles(ref1: refBefore, ref2: refAfter, pattern: specPattern, workingDirectory: workingDirectory)
            for filePath in deletedFiles {
                let projectName = MarkdownClaudeChainSource.matchesSpecPath(filePath) ?? SweepClaudeChainSource.matchesSpecPath(filePath)
                if let projectName {
                    changedProjects.append(
                        AutoStartProject(
                            name: projectName,
                            changeType: .deleted,
                            specPath: filePath
                        )
                    )
                }
            }
        } catch {
            logger.warning("Failed to detect deleted files: \(error)")
        }
        
        return changedProjects
    }
    
    public func determineNewProjects(projects: [AutoStartProject]) -> [AutoStartProject] {
        /**
         * Check which projects have no existing PRs (are truly new)
         *
         * Args:
         *     projects: List of AutoStartProject instances to check
         *
         * Returns:
         *     List of projects that have no existing PRs (new projects)
         *
         * Examples:
         *     let service = AutoStartService("owner/repo", prService)
         *     let changed = [AutoStartProject("proj1", .modified, "path")]
         *     let newProjects = service.determineNewProjects(changed)
         *     newProjects.count  // 1
         */
        var newProjects: [AutoStartProject] = []
        
        for project in projects {
            // Skip deleted projects
            if project.changeType == .deleted {
                continue
            }
            
            do {
                // Use PRService to get open PRs for this project
                let prs = prService.getProjectPrs(projectName: project.name, state: "open")
                
                // If no open PRs exist, this project is ready for auto-start
                if prs.isEmpty {
                    newProjects.append(project)
                    print("  ✓ \(project.name) has no open PRs, ready for auto-start")
                } else {
                    print("  ✗ \(project.name) has \(prs.count) open PR(s), skipping")
                }
            } catch {
                // Log warning, skip project on API failure
                print("⚠️  Error querying GitHub API for \(project.name): \(error)")
                continue
            }
        }
        
        return newProjects
    }
    
    public func shouldAutoTrigger(project: AutoStartProject) -> AutoStartDecision {
        /**
         * Determine whether to auto-trigger a project based on business logic
         *
         * Args:
         *     project: AutoStartProject to evaluate
         *
         * Returns:
         *     AutoStartDecision with trigger decision and reason
         *
         * Examples:
         *     let service = AutoStartService("owner/repo", prService)
         *     let project = AutoStartProject("proj1", .modified, "path")
         *     let decision = service.shouldAutoTrigger(project)
         *     decision.shouldTrigger  // true
         *     decision.reason  // "New project detected"
         */
        // Check if auto-start is disabled
        if !autoStartEnabled {
            return AutoStartDecision(
                project: project,
                shouldTrigger: false,
                reason: "Auto-start is disabled via configuration"
            )
        }
        
        // Deleted projects should never be triggered
        if project.changeType == .deleted {
            return AutoStartDecision(
                project: project,
                shouldTrigger: false,
                reason: "Project spec was deleted"
            )
        }
        
        // Check if project has open PRs
        do {
            let prs = prService.getProjectPrs(projectName: project.name, state: "open")
            
            if prs.isEmpty {
                // No open PRs - ready for work (new project or completed project)
                return AutoStartDecision(
                    project: project,
                    shouldTrigger: true,
                    reason: "No open PRs, ready for work"
                )
            } else {
                // Has open PRs - should not trigger
                return AutoStartDecision(
                    project: project,
                    shouldTrigger: false,
                    reason: "Project has \(prs.count) open PR(s)"
                )
            }
        } catch {
            // On error, default to not triggering
            return AutoStartDecision(
                project: project,
                shouldTrigger: false,
                reason: "Error checking PRs: \(error)"
            )
        }
    }
}