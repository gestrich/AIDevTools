import ArgumentParser
import Foundation
import ClaudeChainService
import ClaudeChainSDK
import ClaudeChainFeature

public struct AutoStartCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "auto-start",
        abstract: "Detect new projects and trigger workflows"
    )
    
    @Option(name: .long, help: "GitHub repository (owner/name)")
    public var repo: String?
    
    @Option(name: .long, help: "Base branch to fetch specs from (default: main)")
    public var baseBranch: String?
    
    @Option(name: .long, help: "Git ref before the push")
    public var refBefore: String?
    
    @Option(name: .long, help: "Git ref after the push")
    public var refAfter: String?
    
    @Option(name: .long, help: "Whether auto-start is enabled (default: true, set to 'false' to disable)")
    public var autoStartEnabled: Bool = true
    
    public init() {}
    
    public func run() async throws {
        let exitCode = try await cmdAutoStart(
            gh: GitHubActions(),
            repo: repo ?? ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"] ?? "",
            baseBranch: baseBranch ?? "main",
            refBefore: refBefore ?? "",
            refAfter: refAfter ?? "",
            autoStartEnabled: autoStartEnabled
        )
        
        if exitCode != 0 {
            throw ExitCode(exitCode)
        }
    }
}

private func cmdAutoStart(
    gh: GitHubActions,
    repo: String,
    baseBranch: String,
    refBefore: String,
    refAfter: String,
    autoStartEnabled: Bool = true
) async throws -> Int32 {
    /**
     * Detect new projects and trigger ClaudeChain workflows for them.
     *
     * This function orchestrates the auto-start workflow:
     * 1. Detect changed spec.md files
     * 2. Determine which projects are new (no existing PRs)
     * 3. Make auto-trigger decisions based on business logic
     * 4. Trigger ClaudeChain workflows for approved projects
     *
     * GitHub Actions outputs:
     *     triggered_projects: Space-separated list of successfully triggered projects
     *     trigger_count: Number of successful triggers
     *     failed_projects: Space-separated list of projects that failed to trigger
     *     projects_to_trigger: (legacy) Space-separated list of projects identified for triggering
     *     project_count: (legacy) Number of projects identified for triggering
     *
     * Args:
     *     gh: GitHub Actions helper instance
     *     repo: GitHub repository (owner/name)
     *     baseBranch: Base branch name (e.g., "main")
     *     refBefore: Git reference before the push (commit SHA)
     *     refAfter: Git reference after the push (commit SHA)
     *     autoStartEnabled: Whether auto-start is enabled (default: True)
     *
     * Returns:
     *     Exit code (0 for success, non-zero for failure)
     */
    print("=== ClaudeChain Auto-Start Detection ===\n")
    print("Repository: \(repo)")
    print("Base branch: \(baseBranch)")
    print("Checking changes: \(String(refBefore.prefix(8)))...\(String(refAfter.prefix(8)))\n")

    // === Initialize services ===
    let prService = PRService(repo: repo)
    let autoStartService = AutoStartService(repo: repo, prService: prService, autoStartEnabled: autoStartEnabled)

    // === Step 1: Detect changed projects ===
    print("=== Step 1/3: Detecting changed projects ===")
    let changedProjects = try await autoStartService.detectChangedProjects(
        refBefore: refBefore,
        refAfter: refAfter,
        specPattern: "claude-chain/*/spec.md"
    )

    if changedProjects.isEmpty {
        print("No spec.md changes detected\n")
        gh.writeOutput(name: "projects_to_trigger", value: "")
        gh.writeOutput(name: "project_count", value: "0")
        return 0
    }

    print("Found \(changedProjects.count) changed project(s):")
    for project in changedProjects {
        print("  - \(project.name) (\(project.changeType.rawValue))")
    }
    print()

    // === Step 2: Determine new projects ===
    print("=== Step 2/3: Determining new projects ===")
    let newProjects = autoStartService.determineNewProjects(projects: changedProjects)

    if newProjects.isEmpty {
        print("\nNo new projects to trigger (all have existing PRs)\n")
        gh.writeOutput(name: "projects_to_trigger", value: "")
        gh.writeOutput(name: "project_count", value: "0")
        return 0
    }

    print("\nFound \(newProjects.count) new project(s) to trigger\n")

    // === Step 3: Make auto-trigger decisions ===
    print("=== Step 3/4: Making auto-trigger decisions ===")
    var projectsToTrigger: [String] = []

    for project in newProjects {
        let decision = autoStartService.shouldAutoTrigger(project: project)

        if decision.shouldTrigger {
            projectsToTrigger.append(project.name)
            print("  ✓ \(project.name): TRIGGER - \(decision.reason)")
        } else {
            print("  ✗ \(project.name): SKIP - \(decision.reason)")
        }
    }

    print()

    // === Step 4: Trigger workflows ===
    var triggeredProjects: [String] = []
    var failedProjects: [String] = []

    if !projectsToTrigger.isEmpty {
        print("=== Step 4/4: Triggering workflows ===")
        let workflowService = WorkflowService()
        let (successful, failed) = workflowService.batchTriggerClaudeChainWorkflows(
            projects: projectsToTrigger,
            baseBranch: baseBranch,
            checkoutRef: refAfter
        )
        triggeredProjects = successful
        failedProjects = failed
        print()
    }

    // === Write outputs ===
    // Write list of successfully triggered projects
    let triggeredOutput = triggeredProjects.isEmpty ? "" : triggeredProjects.joined(separator: " ")
    gh.writeOutput(name: "triggered_projects", value: triggeredOutput)
    gh.writeOutput(name: "trigger_count", value: String(triggeredProjects.count))

    // Write list of failed projects
    let failedOutput = failedProjects.isEmpty ? "" : failedProjects.joined(separator: " ")
    gh.writeOutput(name: "failed_projects", value: failedOutput)

    // Also write legacy projects_to_trigger for backward compatibility
    let projectsOutput = projectsToTrigger.isEmpty ? "" : projectsToTrigger.joined(separator: " ")
    gh.writeOutput(name: "projects_to_trigger", value: projectsOutput)
    gh.writeOutput(name: "project_count", value: String(projectsToTrigger.count))

    // === Summary ===
    if !triggeredProjects.isEmpty {
        print("✅ Auto-start complete")
        print("   Successfully triggered: \(triggeredProjects.count) project(s)")
        print("   Projects: \(triggeredOutput)")
        if !failedProjects.isEmpty {
            print("   ⚠️  Failed triggers: \(failedProjects.count) project(s)")
            print("   Failed projects: \(failedOutput)")
        }
    } else if !projectsToTrigger.isEmpty {
        // Some projects were identified but all triggers failed
        print("❌ Auto-start failed - all triggers failed")
        print("   Failed projects: \(failedOutput)")
    } else {
        print("✅ Auto-start complete (no projects to trigger)")
    }

    return 0
}